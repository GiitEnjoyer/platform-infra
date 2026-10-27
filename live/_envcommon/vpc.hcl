terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../terraform/modules//vpc"
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = {
  name              = local.env_vars.locals.env
  private_cidrs     = local.env_vars.locals.vpc.private_cidrs
  public_cidrs      = local.env_vars.locals.vpc.public_cidrs
  allowed_ssh_cidrs = local.env_vars.locals.vpc.allowed_ssh_cidrs
}
