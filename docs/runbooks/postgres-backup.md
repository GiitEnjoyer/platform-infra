# Runbook: PostgresBackupTooOld / PostgresBackupMissing

**Severity:** critical · **Влияние:** off-site копия устарела; при потере облака RPO вырастет

## Диагностика

```bash
ssh backup-01.prod.example.internal
systemctl status pg-backup.service pg-backup.timer
journalctl -u pg-backup.service --since "-2 days" | tail -100
cat /var/lib/node_exporter/textfile/pg_backup.prom
```

| Симптом в логе | Причина | Действие |
|---|---|---|
| `permission denied` / `403` от Vault | истёк токен AppRole | `vault write auth/approle/role/backup/secret-id` → обновить `/etc/default/pg-backup` |
| `could not connect to server` | реплика недоступна / failover | проверить `c-<id>.ro.mdb.yandexcloud.net`; при длительной недоступности временно снять дамп с rw-хоста |
| `AccessDenied` от S3 DR | роль AWS удалена/изменена | сверить `writer_principal_arns` в `live/prod/dr-bucket` |
| `No space left on device` | локальная ретенция не отработала | `find /var/backups/postgres -mtime +1 -delete` |
| метрик нет совсем | node_exporter остановлен | `systemctl restart node_exporter` |

## Восстановление после устранения

```bash
systemctl start pg-backup.service   # внеплановый запуск
journalctl -fu pg-backup.service
```

Алерт закрывается автоматически, когда `pg_backup_last_success_timestamp_seconds` обновится.

## Проверка восстановимости (раз в месяц)

```bash
aws s3 cp s3://shop-prod-pg-dr-backups/postgres/orders/<file>.dump.zst - \
  | zstd -d | pg_restore --list | head
```

Полное восстановление выполняется на временной ВМ в dev; время восстановления записывается в журнал DR-учений.
