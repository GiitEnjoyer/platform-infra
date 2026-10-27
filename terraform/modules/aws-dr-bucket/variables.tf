variable "bucket_name" {
  description = "Globally unique S3 bucket name for off-site backup copies"
  type        = string
}

variable "retention_days" {
  description = "Object Lock retention (COMPLIANCE mode): backups cannot be deleted even with admin credentials"
  type        = number
  default     = 30
}

variable "glacier_after_days" {
  description = "Move objects to Glacier Instant Retrieval after N days"
  type        = number
  default     = 7
}

variable "expire_after_days" {
  type    = number
  default = 90
}

variable "writer_principal_arns" {
  description = "IAM principals allowed to upload backups (sync job)"
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
