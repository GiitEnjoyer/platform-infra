locals {
  labels = merge(var.labels, { module = "vpc", network = var.name })

  private_subnets = { for i, zone in var.zones : zone => var.private_cidrs[i] }
  public_subnets  = { for i, zone in var.zones : zone => var.public_cidrs[i] }
}

resource "yandex_vpc_network" "this" {
  name      = "${var.name}-net"
  folder_id = var.folder_id
  labels    = local.labels
}

# Single managed NAT gateway: private nodes get egress without public IPs.
resource "yandex_vpc_gateway" "nat" {
  name      = "${var.name}-nat"
  folder_id = var.folder_id
  labels    = local.labels
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private" {
  name       = "${var.name}-private-rt"
  folder_id  = var.folder_id
  network_id = yandex_vpc_network.this.id
  labels     = local.labels

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat.id
  }
}

resource "yandex_vpc_subnet" "private" {
  for_each = local.private_subnets

  name           = "${var.name}-private-${each.key}"
  folder_id      = var.folder_id
  zone           = each.key
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [each.value]
  route_table_id = yandex_vpc_route_table.private.id
  labels         = merge(local.labels, { tier = "private" })
}

resource "yandex_vpc_subnet" "public" {
  for_each = local.public_subnets

  name           = "${var.name}-public-${each.key}"
  folder_id      = var.folder_id
  zone           = each.key
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [each.value]
  labels         = merge(local.labels, { tier = "public" })
}

# Baseline security group for k8s nodes: intra-VPC traffic, LB health checks, NodePorts.
resource "yandex_vpc_security_group" "k8s_nodes" {
  name       = "${var.name}-k8s-nodes"
  folder_id  = var.folder_id
  network_id = yandex_vpc_network.this.id
  labels     = local.labels

  ingress {
    description    = "Intra-VPC traffic (pods, services, nodes)"
    protocol       = "ANY"
    v4_cidr_blocks = concat(var.private_cidrs, var.public_cidrs)
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    description       = "Network load balancer health checks"
    protocol          = "TCP"
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    description    = "NodePort range for external load balancers"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }

  ingress {
    description    = "ICMP for path MTU discovery"
    protocol       = "ICMP"
    v4_cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description    = "Any egress"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "bastion" {
  count = length(var.allowed_ssh_cidrs) > 0 ? 1 : 0

  name       = "${var.name}-bastion"
  folder_id  = var.folder_id
  network_id = yandex_vpc_network.this.id
  labels     = local.labels

  ingress {
    description    = "SSH from trusted networks only"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = var.allowed_ssh_cidrs
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}
