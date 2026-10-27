# dev: cheapest configuration that still mirrors prod topology.
# Preemptible nodes + single-host PostgreSQL: ~70% cheaper than prod-like dev.
locals {
  env                 = "dev"
  cloud_id            = get_env("YC_CLOUD_ID")
  folder_id           = get_env("YC_FOLDER_ID_DEV")
  cost_center         = "engineering"
  state_lock_endpoint = get_env("TF_STATE_LOCK_ENDPOINT")

  vpc = {
    private_cidrs     = ["10.20.0.0/20", "10.20.16.0/20", "10.20.32.0/20"]
    public_cidrs      = ["10.20.240.0/24", "10.20.241.0/24", "10.20.242.0/24"]
    allowed_ssh_cidrs = []
  }

  k8s = {
    version         = "1.30"
    release_channel = "RAPID"
    public_api      = true
    node_groups = {
      apps = {
        cores         = 4
        memory        = 8
        core_fraction = 50
        min           = 1
        max           = 4
        preemptible   = true
      }
    }
  }

  pg = {
    environment = "PRESTABLE"
    ha          = false
    preset      = "s3-c2-m8"
    disk_size   = 20
    databases = {
      orders  = { extensions = ["pg_trgm"] }
      catalog = {}
    }
  }
}
