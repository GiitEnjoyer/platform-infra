# Off-site backups in AWS. State still lives in Yandex Object Storage (root.hcl),
# only the provider is replaced.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../terraform/modules//aws-dr-bucket"
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "eu-central-1"
      default_tags {
        tags = {
          env        = "prod"
          managed_by = "terraform"
          purpose    = "disaster-recovery"
        }
      }
    }
  EOF
}

prevent_destroy = true

inputs = {
  bucket_name           = "shop-prod-pg-dr-backups"
  retention_days        = 30
  writer_principal_arns = [get_env("AWS_BACKUP_SYNC_ROLE_ARN", "arn:aws:iam::000000000000:role/backup-sync")]
  # root.hcl passes folder_id/labels which this module doesn't declare: Terragrunt
  # only sets TF_VAR_* for them, Terraform ignores undeclared ones.
}
