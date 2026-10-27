include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/postgresql.hcl"
  expose = true
}

prevent_destroy = true

inputs = {
  backup_retain_days = 30
}
