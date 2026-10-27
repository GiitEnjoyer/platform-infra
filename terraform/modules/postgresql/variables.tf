variable "name" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "environment" {
  description = "PRODUCTION | PRESTABLE"
  type        = string
  default     = "PRODUCTION"
}

variable "network_id" {
  type = string
}

variable "subnet_ids" {
  description = "Map zone => subnet ID. One host per zone: primary + replicas."
  type        = map(string)
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "pg_version" {
  type    = string
  default = "16"
}

variable "resource_preset_id" {
  description = "Host class, e.g. s3-c2-m8 (2 vCPU / 8 GB)"
  type        = string
  default     = "s3-c2-m8"
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 100
}

variable "disk_type_id" {
  type    = string
  default = "network-ssd"
}

variable "databases" {
  description = "Databases keyed by name; owner is created automatically and its password is stored in Vault"
  type = map(object({
    extensions = optional(list(string), [])
    conn_limit = optional(number, 100)
  }))
}

variable "pg_config" {
  description = "postgresql_config overrides"
  type        = map(string)
  default = {
    max_connections                     = "400"
    shared_preload_libraries            = "SHARED_PRELOAD_LIBRARIES_PG_STAT_STATEMENTS"
    log_min_duration_statement          = "500"
    default_transaction_isolation       = "TRANSACTION_ISOLATION_READ_COMMITTED"
    idle_in_transaction_session_timeout = "60000"
  }
}

variable "backup_retain_days" {
  type    = number
  default = 14
}

variable "vault_kv_mount" {
  description = "Vault KV v2 mount where DB credentials are written"
  type        = string
  default     = "kv"
}

variable "labels" {
  type    = map(string)
  default = {}
}
