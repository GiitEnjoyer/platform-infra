#!/usr/bin/env python3
"""Right-sizing audit: compare container resource requests with real usage.

Queries Prometheus/VictoriaMetrics for every container in the selected
namespaces, computes recommended requests from usage percentiles and estimates
the monthly cost of the gap. Runs weekly in CI (see .gitlab-ci.yml, job
`finops:audit`) and publishes a Markdown report as an artifact.

Rules:
  * CPU request    = p95 of 5m CPU rate over the window * (1 + headroom)
  * Memory request = max working set over the window   * (1 + headroom)
  * Containers whose recommendation differs from the current request by less
    than `--min-change` are skipped (noise).

Only stdlib is used so the script runs in any CI image.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Iterable

# Default on-demand prices (RUB / month). Override with --cpu-price / --mem-price.
DEFAULT_CPU_PRICE_PER_CORE = 2400.0
DEFAULT_MEM_PRICE_PER_GIB = 650.0

GIB = 1024 ** 3

QUERIES = {
    "cpu_request": 'max by (namespace, pod, container) (kube_pod_container_resource_requests{{resource="cpu",namespace=~"{ns}"}})',
    "mem_request": 'max by (namespace, pod, container) (kube_pod_container_resource_requests{{resource="memory",namespace=~"{ns}"}})',
    "cpu_p95": 'quantile_over_time(0.95, rate(container_cpu_usage_seconds_total{{container!="",namespace=~"{ns}"}}[5m])[{window}:5m])',
    "mem_max": 'max_over_time(container_memory_working_set_bytes{{container!="",namespace=~"{ns}"}}[{window}])',
}


@dataclass
class Container:
    namespace: str
    workload: str
    container: str
    replicas: int = 0
    cpu_request: float = 0.0  # cores, per replica
    mem_request: float = 0.0  # bytes, per replica
    cpu_usage: list[float] = field(default_factory=list)  # p95 per pod
    mem_usage: list[float] = field(default_factory=list)  # max per pod

    @property
    def key(self) -> tuple[str, str, str]:
        return self.namespace, self.workload, self.container


@dataclass
class Recommendation:
    namespace: str
    workload: str
    container: str
    replicas: int
    cpu_current: float
    cpu_recommended: float
    mem_current_gib: float
    mem_recommended_gib: float
    monthly_delta_rub: float  # negative = savings

    def as_row(self) -> list[str]:
        return [
            self.namespace,
            self.workload,
            self.container,
            str(self.replicas),
            f"{self.cpu_current:.3f}",
            f"{self.cpu_recommended:.3f}",
            f"{self.mem_current_gib:.2f}",
            f"{self.mem_recommended_gib:.2f}",
            f"{self.monthly_delta_rub:,.0f}".replace(",", " "),
        ]


def workload_from_pod(pod: str) -> str:
    """Strip ReplicaSet hash and pod suffix: api-7d9f8b6c5d-x2k4q -> api.

    StatefulSet pods (db-0) keep their base name without the ordinal.
    """
    parts = pod.split("-")
    if len(parts) >= 3 and len(parts[-1]) == 5 and 8 <= len(parts[-2]) <= 10:
        return "-".join(parts[:-2])
    if len(parts) >= 2 and parts[-1].isdigit():
        return "-".join(parts[:-1])
    return pod


def round_cpu(cores: float) -> float:
    """Round up to 5m granularity, minimum 10m."""
    milli = max(10, int(-(-cores * 1000 // 5) * 5))
    return milli / 1000


def round_mem(bytes_: float) -> float:
    """Round up to 16Mi, minimum 32Mi."""
    step = 16 * 1024 * 1024
    return max(2 * step, -(-bytes_ // step) * step)


def recommend(
    containers: Iterable[Container],
    headroom: float = 0.2,
    min_change: float = 0.15,
    cpu_price: float = DEFAULT_CPU_PRICE_PER_CORE,
    mem_price: float = DEFAULT_MEM_PRICE_PER_GIB,
) -> list[Recommendation]:
    result: list[Recommendation] = []
    for c in containers:
        if not c.cpu_usage or not c.mem_usage or c.replicas == 0:
            continue

        cpu_rec = round_cpu(max(c.cpu_usage) * (1 + headroom))
        mem_rec = round_mem(max(c.mem_usage) * (1 + headroom))

        cpu_change = abs(cpu_rec - c.cpu_request) / c.cpu_request if c.cpu_request else 1.0
        mem_change = abs(mem_rec - c.mem_request) / c.mem_request if c.mem_request else 1.0
        if cpu_change < min_change and mem_change < min_change:
            continue

        delta = c.replicas * (
            (cpu_rec - c.cpu_request) * cpu_price + (mem_rec - c.mem_request) / GIB * mem_price
        )
        result.append(
            Recommendation(
                namespace=c.namespace,
                workload=c.workload,
                container=c.container,
                replicas=c.replicas,
                cpu_current=c.cpu_request,
                cpu_recommended=cpu_rec,
                mem_current_gib=c.mem_request / GIB,
                mem_recommended_gib=mem_rec / GIB,
                monthly_delta_rub=delta,
            )
        )
    # Biggest savings first
    return sorted(result, key=lambda r: r.monthly_delta_rub)


def aggregate(samples: dict[str, list[dict]]) -> list[Container]:
    """Fold per-pod Prometheus samples into per-workload containers."""
    by_key: dict[tuple[str, str, str], Container] = {}
    pods_seen: dict[tuple[str, str, str], set[str]] = {}

    def get(metric: dict) -> Container:
        ns, pod, cont = metric["namespace"], metric["pod"], metric["container"]
        key = (ns, workload_from_pod(pod), cont)
        if key not in by_key:
            by_key[key] = Container(*key)
            pods_seen[key] = set()
        pods_seen[key].add(pod)
        return by_key[key]

    for s in samples.get("cpu_request", []):
        c = get(s["metric"])
        c.cpu_request = max(c.cpu_request, float(s["value"][1]))
    for s in samples.get("mem_request", []):
        c = get(s["metric"])
        c.mem_request = max(c.mem_request, float(s["value"][1]))
    for s in samples.get("cpu_p95", []):
        get(s["metric"]).cpu_usage.append(float(s["value"][1]))
    for s in samples.get("mem_max", []):
        get(s["metric"]).mem_usage.append(float(s["value"][1]))

    for key, c in by_key.items():
        c.replicas = len(pods_seen[key])
    return list(by_key.values())


def query(base_url: str, promql: str, timeout: int = 120) -> list[dict]:
    url = f"{base_url.rstrip('/')}/api/v1/query?" + urllib.parse.urlencode({"query": promql})
    req = urllib.request.Request(url)
    token = os.environ.get("PROM_BEARER_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310 (trusted internal URL)
        payload = json.load(resp)
    if payload.get("status") != "success":
        raise RuntimeError(f"query failed: {payload}")
    return payload["data"]["result"]


def render_markdown(recs: list[Recommendation], window: str) -> str:
    savings = -sum(r.monthly_delta_rub for r in recs if r.monthly_delta_rub < 0)
    extra = sum(r.monthly_delta_rub for r in recs if r.monthly_delta_rub > 0)
    lines = [
        f"# Right-sizing report (window {window})",
        "",
        f"* Potential savings: **{savings:,.0f} ₽/month**".replace(",", " "),
        f"* Under-provisioned workloads need: **{extra:,.0f} ₽/month** more".replace(",", " "),
        "",
        "| namespace | workload | container | replicas | CPU now | CPU rec | Mem now, GiB | Mem rec, GiB | Δ ₽/month |",
        "|---|---|---|---:|---:|---:|---:|---:|---:|",
    ]
    lines += ["| " + " | ".join(r.as_row()) + " |" for r in recs]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--url", default=os.environ.get("PROM_URL", "http://localhost:8429"))
    p.add_argument("--namespaces", default=".*", help="regex, e.g. 'shop|payments'")
    p.add_argument("--window", default="7d")
    p.add_argument("--headroom", type=float, default=0.2)
    p.add_argument("--min-change", type=float, default=0.15)
    p.add_argument("--cpu-price", type=float, default=DEFAULT_CPU_PRICE_PER_CORE)
    p.add_argument("--mem-price", type=float, default=DEFAULT_MEM_PRICE_PER_GIB)
    p.add_argument("--format", choices=["markdown", "csv"], default="markdown")
    p.add_argument("--fail-over", type=float, default=None,
                   help="exit 2 if potential monthly savings exceed this amount (CI gate)")
    args = p.parse_args(argv)

    samples = {
        name: query(args.url, q.format(ns=args.namespaces, window=args.window))
        for name, q in QUERIES.items()
    }
    recs = recommend(aggregate(samples), args.headroom, args.min_change, args.cpu_price, args.mem_price)

    if args.format == "csv":
        w = csv.writer(sys.stdout)
        w.writerow(["namespace", "workload", "container", "replicas", "cpu_now", "cpu_rec",
                    "mem_now_gib", "mem_rec_gib", "delta_rub_month"])
        w.writerows(r.as_row() for r in recs)
    else:
        sys.stdout.write(render_markdown(recs, args.window))

    savings = -sum(r.monthly_delta_rub for r in recs if r.monthly_delta_rub < 0)
    if args.fail_over is not None and savings > args.fail_over:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
