terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../terraform/modules//k8s-cluster"
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

dependency "vpc" {
  config_path = "../vpc"

  # Allows `plan` on a fresh environment before the VPC exists.
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    network_id                  = "mock-network"
    private_subnet_ids          = { "ru-central1-a" = "mock-a", "ru-central1-b" = "mock-b", "ru-central1-d" = "mock-d" }
    k8s_nodes_security_group_id = "mock-sg"
  }
}

inputs = {
  name               = "${local.env_vars.locals.env}-k8s"
  network_id         = dependency.vpc.outputs.network_id
  subnet_ids         = dependency.vpc.outputs.private_subnet_ids
  security_group_ids = [dependency.vpc.outputs.k8s_nodes_security_group_id]
  k8s_version        = local.env_vars.locals.k8s.version
  public_api         = local.env_vars.locals.k8s.public_api
  release_channel    = local.env_vars.locals.k8s.release_channel
  node_groups        = local.env_vars.locals.k8s.node_groups
}
