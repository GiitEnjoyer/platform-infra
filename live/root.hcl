# Root Terragrunt config: remote state + provider generation shared by every stack.
# Layout: live/<env>/<stack>/terragrunt.hcl  ->  state key <env>/<stack>/terraform.tfstate

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  env       = local.env_vars.locals.env
  cloud_id  = local.env_vars.locals.cloud_id
  folder_id = local.env_vars.locals.folder_id

  common_labels = {
    env        = local.env
    managed_by = "terraform"
    repo       = "platform-infra"
    cost_center = local.env_vars.locals.cost_center
  }
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket = "tfstate-${local.cloud_id}"
    key    = "${path_relative_to_include()}/terraform.tfstate"
    region = "ru-central1"

    endpoints = {
      s3       = "https://storage.yandexcloud.net"
      dynamodb = local.env_vars.locals.state_lock_endpoint
    }
    dynamodb_table = "tfstate-lock"
    encrypt        = true

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_bucket_versioning      = true
    skip_bucket_ssencryption    = true
    skip_bucket_root_access     = true
    skip_bucket_enforced_tls    = true
    skip_bucket_public_access_blocking = true
    disable_bucket_update       = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "yandex" {
      cloud_id  = "${local.cloud_id}"
      folder_id = "${local.folder_id}"
      zone      = "ru-central1-a"
      # Credentials: YC_SERVICE_ACCOUNT_KEY_FILE in CI, YC_TOKEN locally.
    }
  EOF
}

inputs = {
  folder_id = local.folder_id
  labels    = local.common_labels
}

terraform {
  extra_arguments "parallelism" {
    commands  = ["plan", "apply", "destroy"]
    arguments = ["-parallelism=20"]
  }

  extra_arguments "plan_out" {
    commands  = ["plan"]
    arguments = ["-lock-timeout=5m"]
  }
}
