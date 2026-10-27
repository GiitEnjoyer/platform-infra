variable "name" {
  description = "Network name prefix, e.g. prod"
  type        = string
}

variable "folder_id" {
  description = "Yandex Cloud folder ID"
  type        = string
}

variable "zones" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["ru-central1-a", "ru-central1-b", "ru-central1-d"]
}

variable "private_cidrs" {
  description = "Private subnets (k8s nodes, databases), one per zone"
  type        = list(string)
  default     = ["10.10.0.0/20", "10.10.16.0/20", "10.10.32.0/20"]

  validation {
    condition     = alltrue([for c in var.private_cidrs : can(cidrnetmask(c))])
    error_message = "All private_cidrs must be valid IPv4 CIDR blocks."
  }
}

variable "public_cidrs" {
  description = "Public subnets (load balancers, bastion), one per zone"
  type        = list(string)
  default     = ["10.10.240.0/24", "10.10.241.0/24", "10.10.242.0/24"]
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to reach the bastion over SSH (office/VPN egress)"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels applied to all resources (used by FinOps cost reports)"
  type        = map(string)
  default     = {}
}
