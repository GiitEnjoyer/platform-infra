# prod: regional HA control plane, dedicated system node group,
# PostgreSQL with a host in every availability zone.
locals {
  env                 = "prod"
  cloud_id            = get_env("YC_CLOUD_ID")
  folder_id           = get_env("YC_FOLDER_ID_PROD")
  cost_center         = "platform"
  state_lock_endpoint = get_env("TF_STATE_LOCK_ENDPOINT")

  vpc = {
    private_cidrs     = ["10.10.0.0/20", "10.10.16.0/20", "10.10.32.0/20"]
    public_cidrs      = ["10.10.240.0/24", "10.10.241.0/24", "10.10.242.0/24"]
    allowed_ssh_cidrs = ["203.0.113.10/32"] # VPN egress (documentation range)
  }

  k8s = {
    version         = "1.30"
    release_channel = "STABLE"
    public_api      = false
    node_groups = {
      system = {
        cores  = 4
        memory = 16
        min    = 3
        max    = 3
        taints = ["dedicated=system:NoSchedule"]
        labels = { role = "system" }
      }
      apps = {
        cores  = 16
        memory = 32
        min    = 6
        max    = 30
        labels = { role = "apps" }
      }
      batch = {
        cores       = 8
        memory      = 16
        min         = 0
        max         = 10
        preemptible = true
        taints      = ["workload=batch:NoSchedule"]
        labels      = { role = "batch" }
      }
    }
  }

  pg = {
    environment = "PRODUCTION"
    ha          = true
    preset      = "s3-c8-m32"
    disk_size   = 500
    databases = {
      orders  = { extensions = ["pg_trgm"], conn_limit = 300 }
      catalog = { conn_limit = 200 }
    }
  }
}
