locals {
  labels   = merge(var.labels, { module = "k8s-cluster", cluster = var.name })
  regional = length(var.subnet_ids) >= 3
  zones    = sort(keys(var.subnet_ids))
}

# --- Service accounts ---------------------------------------------------------
# Cluster SA manages cloud resources (LBs, disks); node SA only pulls images.
resource "yandex_iam_service_account" "cluster" {
  name      = "${var.name}-cluster-sa"
  folder_id = var.folder_id
}

resource "yandex_iam_service_account" "nodes" {
  name      = "${var.name}-nodes-sa"
  folder_id = var.folder_id
}

resource "yandex_resourcemanager_folder_iam_member" "cluster" {
  for_each = toset([
    "k8s.clusters.agent",
    "vpc.publicAdmin",
    "load-balancer.admin",
    "logging.writer",
  ])

  folder_id = var.folder_id
  role      = each.value
  member    = "serviceAccount:${yandex_iam_service_account.cluster.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "nodes_registry" {
  folder_id = var.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.nodes.id}"
}

# --- Secrets encryption at rest (etcd) ----------------------------------------
resource "yandex_kms_symmetric_key" "etcd" {
  name              = "${var.name}-etcd"
  folder_id         = var.folder_id
  default_algorithm = "AES_256"
  rotation_period   = "8760h"
  labels            = local.labels
}

resource "yandex_kms_symmetric_key_iam_binding" "etcd" {
  symmetric_key_id = yandex_kms_symmetric_key.etcd.id
  role             = "kms.keys.encrypterDecrypter"
  members          = ["serviceAccount:${yandex_iam_service_account.cluster.id}"]
}

# --- Control plane ------------------------------------------------------------
resource "yandex_kubernetes_cluster" "this" {
  name        = var.name
  folder_id   = var.folder_id
  network_id  = var.network_id
  labels      = local.labels
  description = "Managed by Terraform"

  service_account_id      = yandex_iam_service_account.cluster.id
  node_service_account_id = yandex_iam_service_account.nodes.id
  release_channel         = var.release_channel
  cluster_ipv4_range      = var.cluster_ipv4_range
  service_ipv4_range      = var.service_ipv4_range
  network_policy_provider = "CALICO"

  kms_provider {
    key_id = yandex_kms_symmetric_key.etcd.id
  }

  master {
    version            = var.k8s_version
    public_ip          = var.public_api
    security_group_ids = var.security_group_ids

    dynamic "regional" {
      for_each = local.regional ? [1] : []
      content {
        region = "ru-central1"
        dynamic "location" {
          for_each = var.subnet_ids
          content {
            zone      = location.key
            subnet_id = location.value
          }
        }
      }
    }

    dynamic "zonal" {
      for_each = local.regional ? [] : [1]
      content {
        zone      = local.zones[0]
        subnet_id = var.subnet_ids[local.zones[0]]
      }
    }

    maintenance_policy {
      auto_upgrade = true
      maintenance_window {
        day        = var.maintenance_window.day
        start_time = var.maintenance_window.start_time
        duration   = var.maintenance_window.duration
      }
    }

    master_logging {
      enabled                    = true
      folder_id                  = var.folder_id
      kube_apiserver_enabled     = true
      cluster_autoscaler_enabled = true
      events_enabled             = true
      audit_enabled              = true
    }
  }

  depends_on = [
    yandex_resourcemanager_folder_iam_member.cluster,
    yandex_resourcemanager_folder_iam_member.nodes_registry,
    yandex_kms_symmetric_key_iam_binding.etcd,
  ]
}

# --- Worker node groups (cluster-autoscaler built in) -------------------------
resource "yandex_kubernetes_node_group" "this" {
  for_each = var.node_groups

  cluster_id  = yandex_kubernetes_cluster.this.id
  name        = "${var.name}-${each.key}"
  version     = var.k8s_version
  labels      = local.labels
  node_labels = merge({ "node-group" = each.key }, each.value.labels)
  node_taints = each.value.taints

  instance_template {
    platform_id = each.value.platform_id

    resources {
      cores         = each.value.cores
      memory        = each.value.memory
      core_fraction = each.value.core_fraction
    }

    boot_disk {
      type = each.value.disk_type
      size = each.value.disk_size
    }

    scheduling_policy {
      preemptible = each.value.preemptible
    }

    network_interface {
      subnet_ids         = values(var.subnet_ids)
      security_group_ids = var.security_group_ids
      nat                = false
    }

    container_runtime {
      type = "containerd"
    }

    metadata = {
      enable-oslogin = "true"
    }
  }

  scale_policy {
    auto_scale {
      min     = each.value.min
      max     = each.value.max
      initial = each.value.min
    }
  }

  allocation_policy {
    dynamic "location" {
      for_each = local.zones
      content {
        zone = location.value
      }
    }
  }

  deploy_policy {
    max_expansion   = 2
    max_unavailable = 1
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true
    maintenance_window {
      day        = var.maintenance_window.day
      start_time = var.maintenance_window.start_time
      duration   = var.maintenance_window.duration
    }
  }
}
