output "network_id" {
  description = "VPC network ID"
  value       = yandex_vpc_network.this.id
}

output "private_subnet_ids" {
  description = "Map zone => private subnet ID"
  value       = { for zone, s in yandex_vpc_subnet.private : zone => s.id }
}

output "public_subnet_ids" {
  description = "Map zone => public subnet ID"
  value       = { for zone, s in yandex_vpc_subnet.public : zone => s.id }
}

output "k8s_nodes_security_group_id" {
  description = "Security group for Kubernetes worker nodes"
  value       = yandex_vpc_security_group.k8s_nodes.id
}

output "bastion_security_group_id" {
  description = "Security group for bastion host (null when SSH is closed)"
  value       = try(yandex_vpc_security_group.bastion[0].id, null)
}
