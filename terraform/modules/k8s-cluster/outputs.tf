output "cluster_id" {
  value = yandex_kubernetes_cluster.this.id
}

output "cluster_name" {
  value = yandex_kubernetes_cluster.this.name
}

output "internal_endpoint" {
  value = yandex_kubernetes_cluster.this.master[0].internal_v4_endpoint
}

output "external_endpoint" {
  value = yandex_kubernetes_cluster.this.master[0].external_v4_endpoint
}

output "ca_certificate" {
  value     = yandex_kubernetes_cluster.this.master[0].cluster_ca_certificate
  sensitive = true
}

output "node_group_ids" {
  value = { for k, g in yandex_kubernetes_node_group.this : k => g.id }
}

output "kubeconfig_command" {
  description = "Command to fetch kubeconfig"
  value       = "yc managed-kubernetes cluster get-credentials ${yandex_kubernetes_cluster.this.name} --${var.public_api ? "external" : "internal"} --folder-id ${var.folder_id}"
}
