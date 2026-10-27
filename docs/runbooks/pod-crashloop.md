# Runbook: PodCrashLooping / ContainerOOMKilled

```bash
kubectl -n <ns> describe pod <pod>                 # Last State, Reason, Exit Code, Events
kubectl -n <ns> logs <pod> -c <container> --previous
kubectl -n <ns> rollout history deploy/<name>
```

| Exit code / Reason | Значение | Действие |
|---|---|---|
| `OOMKilled` (137) | превышен memory limit | сравнить с `container_memory_working_set_bytes`; поднять limit в values чарта через MR |
| 137 без OOM | не прошла liveness-проба / SIGKILL после grace period | проверить пробы и время старта, `startupProbe` |
| 1 / 2 | ошибка приложения или конфигурации | логи `--previous`; часто — недоступен Vault или БД при старте |
| `CreateContainerConfigError` | нет ConfigMap/Secret | `kubectl get events` |
| `ImagePullBackOff` | нет образа / прав registry | проверить тег в релизе Helm |

## Если проблема появилась после релиза

```bash
helm -n <ns> history <release>
helm -n <ns> rollback <release> <revision>
```

Для сервисов с canary-деплоем сначала проверить, что упали только поды `track=canary`: пайплайн откатит их сам по SLO-гейту.
