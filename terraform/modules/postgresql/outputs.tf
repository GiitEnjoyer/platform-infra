output "cluster_id" {
  value = yandex_mdb_postgresql_cluster.this.id
}

output "rw_fqdn" {
  description = "Special FQDN that always points to the current primary"
  value       = "c-${yandex_mdb_postgresql_cluster.this.id}.rw.mdb.yandexcloud.net"
}

output "ro_fqdn" {
  description = "Special FQDN that points to the most up-to-date replica"
  value       = "c-${yandex_mdb_postgresql_cluster.this.id}.ro.mdb.yandexcloud.net"
}

output "vault_paths" {
  description = "Vault KV paths with credentials per database"
  value       = { for k, s in vault_kv_secret_v2.db : k => "${var.vault_kv_mount}/data/${s.name}" }
}
