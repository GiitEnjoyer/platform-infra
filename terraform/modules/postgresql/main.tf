locals {
  labels = merge(var.labels, { module = "postgresql", cluster = var.name })
}

resource "yandex_mdb_postgresql_cluster" "this" {
  name                = var.name
  folder_id           = var.folder_id
  environment         = var.environment
  network_id          = var.network_id
  security_group_ids  = var.security_group_ids
  labels              = local.labels
  deletion_protection = var.environment == "PRODUCTION"

  config {
    version = var.pg_version

    resources {
      resource_preset_id = var.resource_preset_id
      disk_type_id       = var.disk_type_id
      disk_size          = var.disk_size
    }

    disk_size_autoscaling {
      disk_size_limit           = var.disk_size * 3
      planned_usage_threshold   = 80
      emergency_usage_threshold = 90
    }

    backup_window_start {
      hours   = 1
      minutes = 0
    }
    backup_retain_period_days = var.backup_retain_days

    performance_diagnostics {
      enabled                      = true
      sessions_sampling_interval   = 60
      statements_sampling_interval = 600
    }

    pooler_config {
      pool_discard = false
      pooling_mode = "TRANSACTION"
    }

    postgresql_config = var.pg_config
  }

  # One host per AZ. Managed service promotes a replica automatically on primary failure.
  dynamic "host" {
    for_each = var.subnet_ids
    content {
      zone      = host.key
      subnet_id = host.value
      name      = "${var.name}-${host.key}"
    }
  }

  maintenance_window {
    type = "WEEKLY"
    day  = "SUN"
    hour = 3
  }
}

resource "random_password" "owner" {
  for_each = var.databases

  length           = 32
  special          = true
  override_special = "-_"
}

resource "yandex_mdb_postgresql_user" "owner" {
  for_each = var.databases

  cluster_id = yandex_mdb_postgresql_cluster.this.id
  name       = "${each.key}_owner"
  password   = random_password.owner[each.key].result
  conn_limit = each.value.conn_limit
}

resource "yandex_mdb_postgresql_database" "this" {
  for_each = var.databases

  cluster_id = yandex_mdb_postgresql_cluster.this.id
  name       = each.key
  owner      = yandex_mdb_postgresql_user.owner[each.key].name
  lc_collate = "en_US.UTF-8"
  lc_type    = "en_US.UTF-8"

  dynamic "extension" {
    for_each = each.value.extensions
    content {
      name = extension.value
    }
  }
}

# Applications never see Terraform outputs: credentials go straight to Vault,
# Vault Agent Injector renders them into pods (see kubernetes/platform/values/vault.yaml).
resource "vault_kv_secret_v2" "db" {
  for_each = var.databases

  mount = var.vault_kv_mount
  name  = "postgres/${var.name}/${each.key}"

  data_json = jsonencode({
    host     = "c-${yandex_mdb_postgresql_cluster.this.id}.rw.mdb.yandexcloud.net"
    ro_host  = "c-${yandex_mdb_postgresql_cluster.this.id}.ro.mdb.yandexcloud.net"
    port     = 6432
    database = each.key
    username = yandex_mdb_postgresql_user.owner[each.key].name
    password = random_password.owner[each.key].result
    sslmode  = "verify-full"
  })
}
