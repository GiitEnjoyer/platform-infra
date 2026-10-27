variable "name" {
  description = "Cluster name"
  type        = string
}

variable "folder_id" {
  description = "Yandex Cloud folder ID"
  type        = string
}

variable "network_id" {
  description = "VPC network ID"
  type        = string
}

variable "subnet_ids" {
  description = "Map zone => private subnet ID. Three zones give a regional (HA) master."
  type        = map(string)
}

variable "security_group_ids" {
  description = "Security groups attached to the master and nodes"
  type        = list(string)
}

variable "k8s_version" {
  description = "Kubernetes minor version"
  type        = string
  default     = "1.30"
}

variable "release_channel" {
  description = "RAPID | REGULAR | STABLE"
  type        = string
  default     = "REGULAR"
}

variable "public_api" {
  description = "Expose API server on a public IP (dev only; prod goes through VPN/bastion)"
  type        = bool
  default     = false
}

variable "cluster_ipv4_range" {
  type    = string
  default = "10.112.0.0/16"
}

variable "service_ipv4_range" {
  type    = string
  default = "10.96.0.0/16"
}

variable "node_groups" {
  description = <<-EOT
    Node groups keyed by name. Example:
      system = { cores = 4, memory = 8, min = 3, max = 3, preemptible = false,
                 taints = ["dedicated=system:NoSchedule"], labels = { role = "system" } }
      apps   = { cores = 8, memory = 16, min = 3, max = 12, preemptible = false }
  EOT
  type = map(object({
    cores         = number
    memory        = number
    core_fraction = optional(number, 100)
    disk_size     = optional(number, 64)
    disk_type     = optional(string, "network-ssd")
    platform_id   = optional(string, "standard-v3")
    min           = number
    max           = number
    preemptible   = optional(bool, false)
    taints        = optional(list(string), [])
    labels        = optional(map(string), {})
  }))

  validation {
    condition     = alltrue([for g in values(var.node_groups) : g.min <= g.max])
    error_message = "For every node group min must be <= max."
  }
}

variable "maintenance_window" {
  description = "Weekly maintenance window (UTC) for master and node auto-upgrades"
  type = object({
    day        = string
    start_time = string
    duration   = string
  })
  default = {
    day        = "sunday"
    start_time = "01:00"
    duration   = "3h"
  }
}

variable "labels" {
  type    = map(string)
  default = {}
}
