import resource_audit as ra

GIB = ra.GIB
MIB = 1024 * 1024


def sample(metric: dict, value: float) -> dict:
    return {"metric": metric, "value": [0, str(value)]}


def test_workload_from_pod_deployment():
    assert ra.workload_from_pod("catalog-api-7d9f8b6c5d-x2k4q") == "catalog-api"


def test_workload_from_pod_statefulset():
    assert ra.workload_from_pod("rabbitmq-2") == "rabbitmq"


def test_workload_from_pod_plain():
    assert ra.workload_from_pod("standalone") == "standalone"


def test_rounding():
    assert ra.round_cpu(0.0001) == 0.010
    assert ra.round_cpu(0.1234) == 0.125
    assert ra.round_mem(1) == 32 * MIB
    assert ra.round_mem(100 * MIB) == 112 * MIB


def test_overprovisioned_container_produces_savings():
    c = ra.Container("shop", "orders", "app", replicas=4,
                     cpu_request=2.0, mem_request=4 * GIB,
                     cpu_usage=[0.30, 0.40], mem_usage=[900 * MIB, 1000 * MIB])
    [rec] = ra.recommend([c], headroom=0.2, cpu_price=1000, mem_price=100)
    assert rec.cpu_recommended == 0.48
    assert rec.mem_recommended_gib < 1.2
    assert rec.monthly_delta_rub < 0  # savings
    # 4 replicas * (0.48 - 2.0) cores * 1000 = -6080 for CPU alone
    assert rec.monthly_delta_rub < -6000


def test_underprovisioned_container_is_reported_as_extra_cost():
    c = ra.Container("shop", "search", "app", replicas=2,
                     cpu_request=0.1, mem_request=256 * MIB,
                     cpu_usage=[0.5], mem_usage=[600 * MIB])
    [rec] = ra.recommend([c])
    assert rec.cpu_recommended > rec.cpu_current
    assert rec.monthly_delta_rub > 0


def test_small_change_is_skipped():
    c = ra.Container("shop", "gw", "app", replicas=3,
                     cpu_request=0.5, mem_request=512 * MIB,
                     cpu_usage=[0.40], mem_usage=[420 * MIB])
    assert ra.recommend([c], headroom=0.2, min_change=0.15) == []


def test_aggregate_groups_pods_into_workload():
    pod_a = {"namespace": "shop", "pod": "orders-5f6d7c8b9a-aaaaa", "container": "app"}
    pod_b = {"namespace": "shop", "pod": "orders-5f6d7c8b9a-bbbbb", "container": "app"}
    samples = {
        "cpu_request": [sample(pod_a, 1), sample(pod_b, 1)],
        "mem_request": [sample(pod_a, GIB), sample(pod_b, GIB)],
        "cpu_p95": [sample(pod_a, 0.2), sample(pod_b, 0.3)],
        "mem_max": [sample(pod_a, 300 * MIB), sample(pod_b, 350 * MIB)],
    }
    [c] = ra.aggregate(samples)
    assert c.workload == "orders"
    assert c.replicas == 2
    assert c.cpu_request == 1
    assert sorted(c.cpu_usage) == [0.2, 0.3]


def test_markdown_report_contains_totals():
    c = ra.Container("shop", "orders", "app", replicas=1, cpu_request=1, mem_request=GIB,
                     cpu_usage=[0.1], mem_usage=[100 * MIB])
    md = ra.render_markdown(ra.recommend([c]), "7d")
    assert "Potential savings" in md
    assert "| shop | orders | app |" in md


def test_main_fail_over_gate(monkeypatch):
    pod = {"namespace": "shop", "pod": "orders-5f6d7c8b9a-aaaaa", "container": "app"}
    canned = {
        "cpu_request": [sample(pod, 4)],
        "mem_request": [sample(pod, 8 * GIB)],
        "cpu_p95": [sample(pod, 0.1)],
        "mem_max": [sample(pod, 200 * MIB)],
    }

    def fake_query(_url, promql, timeout=120):
        if "resource=\"cpu\"" in promql:
            return canned["cpu_request"]
        if "resource=\"memory\"" in promql:
            return canned["mem_request"]
        if "quantile_over_time" in promql:
            return canned["cpu_p95"]
        return canned["mem_max"]

    monkeypatch.setattr(ra, "query", fake_query)
    assert ra.main(["--fail-over", "1000"]) == 2
    assert ra.main(["--fail-over", "10000000"]) == 0
