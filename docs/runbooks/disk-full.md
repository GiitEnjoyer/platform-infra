# Runbook: NodeFilesystemAlmostFull / NodeFilesystemWillFillIn4h

## Узел Kubernetes

```bash
kubectl get node <node> -o wide
kubectl debug node/<node> -it --image=busybox -- chroot /host sh
du -xh /var/lib/containerd --max-depth=2 | sort -h | tail
crictl rmi --prune                         # неиспользуемые образы
journalctl --vacuum-size=500M
```

Если заполнение вызвано подом (emptyDir, логи в файл): найти через `kubectl get pods -A -o wide --field-selector spec.nodeName=<node>`, договориться с командой о лимите `ephemeral-storage`.

Если нужно срочно освободить узел: `kubectl cordon <node> && kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`. Cluster-autoscaler поднимет замену; повреждённый узел пересоздаётся через auto-repair.

## ВМ вне Kubernetes

```bash
df -h; du -xh / --max-depth=2 2>/dev/null | sort -h | tail -20
```

Типичные причины: локальные бэкапы (`/var/backups`), логи приложений без ротации, Docker-образы на раннерах (`docker system prune -af --filter until=72h`).

## После инцидента

Если `predict_linear` сработал из-за органического роста — увеличить диск через Terraform (`disk_size` в `env.hcl`), а не вручную в консоли, иначе появится drift.
