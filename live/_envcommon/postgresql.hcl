terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../terraform/modules//postgresql"
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    network_id         = "mock-network"
    private_subnet_ids = { "ru-central1-a" = "mock-a" }
  }
}

generate "vault_provider" {
  path      = "vault_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "vault" {
      # VAULT_ADDR / VAULT_TOKEN come from CI (JWT auth, short-lived token)
    }
  EOF
}

inputs = {
  name               = "${local.env_vars.locals.env}-pg"
  environment        = local.env_vars.locals.pg.environment
  network_id         = dependency.vpc.outputs.network_id
  subnet_ids         = local.env_vars.locals.pg.ha ? dependency.vpc.outputs.private_subnet_ids : { for k, v in dependency.vpc.outputs.private_subnet_ids : k => v if k == "ru-central1-a" }
  resource_preset_id = local.env_vars.locals.pg.preset
  disk_size          = local.env_vars.locals.pg.disk_size
  databases          = local.env_vars.locals.pg.databases
}
