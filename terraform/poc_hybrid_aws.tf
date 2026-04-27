variable "enable_poc_hybrid_aws" {
  description = "Enable the AWS external-node hybrid PoC resources."
  type        = bool
  default     = false
}

variable "poc_hybrid_aws_region" {
  description = "AWS region used for the hybrid external node PoC."
  type        = string
  default     = "eu-central-1"
}

variable "poc_hybrid_aws_vpc_cidr" {
  description = "CIDR block for the hybrid PoC VPC."
  type        = string
  default     = "192.168.200.0/24"
}

variable "poc_hybrid_aws_public_subnet_cidr" {
  description = "CIDR block for the hybrid PoC public subnet."
  type        = string
  default     = "192.168.200.0/25"
}

variable "poc_hybrid_aws_instance_type" {
  description = "EC2 instance type for the external node."
  type        = string
  default     = "t3a.medium"
}

variable "poc_hybrid_aws_key_pair_name" {
  description = "Optional pre-created AWS key pair name for SSH access."
  type        = string
  default     = ""
}

variable "poc_hybrid_allowed_ssh_cidrs" {
  description = "Trusted source CIDRs allowed to SSH to the external node."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "poc_hybrid_wireguard_tunnel_cidr" {
  description = "CIDR for the point-to-point WireGuard tunnel."
  type        = string
  default     = "10.250.0.0/30"
}

variable "poc_hybrid_wireguard_nat_tunnel_ip" {
  description = "Hetzner NAT-side tunnel IP address."
  type        = string
  default     = "10.250.0.1"
}

variable "poc_hybrid_wireguard_aws_tunnel_ip" {
  description = "AWS external-node tunnel IP address."
  type        = string
  default     = "10.250.0.2"
}

variable "poc_hybrid_wireguard_port" {
  description = "WireGuard UDP listen port."
  type        = number
  default     = 51820
}

variable "poc_hybrid_wireguard_nat_public_key" {
  description = "WireGuard public key for the Hetzner NAT router peer."
  type        = string
  default     = ""
}

variable "override_wg_nat_public_ip" {
  description = "Public IPv4 address for the Hetzner NAT router."
  type        = string
  default     = ""
}

variable "override_k3s_control_url" {
  description = "K3s server URL reachable from AWS over the WireGuard tunnel."
  type        = string
  default     = ""
}

variable "poc_hybrid_install_k3s_agent" {
  description = "Install and start k3s-agent on the EC2 external node."
  type        = bool
  default     = true
}

variable "poc_hybrid_node_labels" {
  description = "Additional labels to apply to the AWS external node."
  type        = list(string)
  default     = ["topology.s8.io/location=aws-external"]
}

variable "poc_hybrid_node_taints" {
  description = "Additional taints to apply to the AWS external node."
  type        = list(string)
  default     = ["topology.s8.io/location=aws-external:NoSchedule"]
}

locals {
  poc_hybrid_enabled = var.enable_poc_hybrid_aws && var.nat_router != null

  poc_hybrid_nat_public_ip = trimspace(var.override_wg_nat_public_ip) != "" ? var.override_wg_nat_public_ip : try(hcloud_server.nat_router[0].ipv4_address, "")

  poc_hybrid_k3s_url = trimspace(var.override_k3s_control_url) != "" ? var.override_k3s_control_url : local.k3s_endpoint

  poc_hybrid_common_tags = merge(local.tags, {
    Component = "hybrid-aws-external-node"
    Scope     = "poc-demo2"
  })

  poc_hybrid_k3s_label_args = join(" ", [for label in var.poc_hybrid_node_labels : format("--node-label '%s'", label)])
  poc_hybrid_k3s_taint_args = join(" ", [for taint in var.poc_hybrid_node_taints : format("--node-taint '%s'", taint)])
}

data "aws_availability_zones" "poc_hybrid" {
  count = local.poc_hybrid_enabled ? 1 : 0

  state = "available"
}

data "aws_ami" "poc_hybrid_al2023" {
  count = local.poc_hybrid_enabled ? 1 : 0

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "poc_hybrid" {
  count = local.poc_hybrid_enabled ? 1 : 0

  cidr_block           = var.poc_hybrid_aws_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.poc_hybrid_common_tags, {
    Name = "${var.cluster_name}-poc-hybrid-vpc"
  })
}

resource "aws_internet_gateway" "poc_hybrid" {
  count = local.poc_hybrid_enabled ? 1 : 0

  vpc_id = aws_vpc.poc_hybrid[0].id

  tags = merge(local.poc_hybrid_common_tags, {
    Name = "${var.cluster_name}-poc-hybrid-igw"
  })
}

resource "aws_subnet" "poc_hybrid_public" {
  count = local.poc_hybrid_enabled ? 1 : 0

  vpc_id                  = aws_vpc.poc_hybrid[0].id
  cidr_block              = var.poc_hybrid_aws_public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.poc_hybrid[0].names[0]

  tags = merge(local.poc_hybrid_common_tags, {
    Name = "${var.cluster_name}-poc-hybrid-public-subnet"
  })
}

resource "aws_route_table" "poc_hybrid_public" {
  count = local.poc_hybrid_enabled ? 1 : 0

  vpc_id = aws_vpc.poc_hybrid[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.poc_hybrid[0].id
  }

  tags = merge(local.poc_hybrid_common_tags, {
    Name = "${var.cluster_name}-poc-hybrid-public-rt"
  })
}

resource "aws_route_table_association" "poc_hybrid_public" {
  count = local.poc_hybrid_enabled ? 1 : 0

  subnet_id      = aws_subnet.poc_hybrid_public[0].id
  route_table_id = aws_route_table.poc_hybrid_public[0].id
}

resource "aws_security_group" "poc_hybrid_external_node" {
  count = local.poc_hybrid_enabled ? 1 : 0

  name        = "${var.cluster_name}-poc-hybrid-external-node"
  description = "Security group for AWS external k3s node"
  vpc_id      = aws_vpc.poc_hybrid[0].id

  ingress {
    description = "WireGuard"
    from_port   = var.poc_hybrid_wireguard_port
    to_port     = var.poc_hybrid_wireguard_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.poc_hybrid_allowed_ssh_cidrs
  }

  ingress {
    description = "Kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.network_ipv4_cidr, var.cluster_ipv4_cidr]
  }

  ingress {
    description = "NodePort range"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.network_ipv4_cidr, var.cluster_ipv4_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.poc_hybrid_common_tags, {
    Name = "${var.cluster_name}-poc-hybrid-external-node-sg"
  })
}

resource "random_id" "poc_hybrid_wireguard_private_key_nat" {
  count = local.poc_hybrid_enabled ? 1 : 0

  byte_length = 32
}

resource "random_id" "poc_hybrid_wireguard_private_key_aws" {
  count = local.poc_hybrid_enabled ? 1 : 0

  byte_length = 32
}

resource "wireguard_asymmetric_key" "nat" {
  count = local.poc_hybrid_enabled ? 1 : 0
}

resource "wireguard_asymmetric_key" "aws" {
  count = local.poc_hybrid_enabled ? 1 : 0
}

resource "aws_instance" "poc_hybrid_external_node" {
  count = local.poc_hybrid_enabled ? 1 : 0

  ami                         = data.aws_ami.poc_hybrid_al2023[0].id
  instance_type               = var.poc_hybrid_aws_instance_type
  subnet_id                   = aws_subnet.poc_hybrid_public[0].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.poc_hybrid_external_node[0].id]
  key_name                    = trimspace(var.poc_hybrid_aws_key_pair_name) == "" ? null : var.poc_hybrid_aws_key_pair_name

  user_data = <<-EOF
              #!/usr/bin/env bash
              set -euxo pipefail

              dnf install -y wireguard-tools
              modprobe wireguard || true

              mkdir -p /etc/wireguard
              chmod 700 /etc/wireguard

              cat > /etc/wireguard/privatekey <<'KEY'
              ${wireguard_asymmetric_key.aws[0].private_key}
              KEY
              chmod 600 /etc/wireguard/privatekey

              # Derive and persist the public key for validation scripts.
              wg pubkey < /etc/wireguard/privatekey > /etc/wireguard/publickey
              chmod 644 /etc/wireguard/publickey

              if [[ -n "${wireguard_asymmetric_key.nat[0].public_key}" && -n "${local.poc_hybrid_nat_public_ip}" ]]; then
                cat > /etc/wireguard/wg0.conf <<'WGCONF'
              [Interface]
              Address = ${var.poc_hybrid_wireguard_aws_tunnel_ip}/30
              ListenPort = ${var.poc_hybrid_wireguard_port}
              PrivateKey = ${wireguard_asymmetric_key.aws[0].private_key}

              [Peer]
              PublicKey = ${wireguard_asymmetric_key.nat[0].public_key}
              Endpoint = ${local.poc_hybrid_nat_public_ip}:${var.poc_hybrid_wireguard_port}
              AllowedIPs = ${var.network_ipv4_cidr},${var.cluster_ipv4_cidr},${var.service_ipv4_cidr},${var.poc_hybrid_wireguard_tunnel_cidr}
              PersistentKeepalive = 25
              WGCONF

                systemctl enable --now wg-quick@wg0
                ip route replace ${var.network_ipv4_cidr} via ${var.poc_hybrid_wireguard_nat_tunnel_ip} dev wg0
                ip route replace ${var.cluster_ipv4_cidr} via ${var.poc_hybrid_wireguard_nat_tunnel_ip} dev wg0
                ip route replace ${var.service_ipv4_cidr} via ${var.poc_hybrid_wireguard_nat_tunnel_ip} dev wg0
              fi

              %{if var.poc_hybrid_install_k3s_agent}
              export K3S_URL="${local.poc_hybrid_k3s_url}"
              export K3S_TOKEN="${local.k3s_token}"
              TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
              PRIVATE_IP=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
              INSTANCE_ID=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

              if [[ -n "$K3S_URL" && -n "$K3S_TOKEN" ]]; then
                curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true sh -s - \
                  agent \
                  --node-name "edge-node-external" \
                  --node-ip "$PRIVATE_IP" \
                  --kubelet-arg="cloud-provider=external" \
                  --kubelet-arg="provider-id=aws://${var.poc_hybrid_aws_region}/$INSTANCE_ID" \
                  ${local.poc_hybrid_k3s_label_args} \
                  ${local.poc_hybrid_k3s_taint_args}

                systemctl enable --now k3s-agent
              fi
              %{endif}
              EOF

  tags = merge(local.poc_hybrid_common_tags, {
    Name = "${var.cluster_name}-poc-hybrid-aws-external-node"
  })
}

resource "terraform_data" "poc_hybrid_nat_wireguard_config" {
  count = local.poc_hybrid_enabled && var.nat_router != null ? 1 : 0

  triggers_replace = {
    aws_public_ip = aws_instance.poc_hybrid_external_node[0].public_ip
  }

  connection {
    user           = "nat-router"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = hcloud_server.nat_router[0].ipv4_address
    port           = var.ssh_port
  }

  provisioner "file" {
    content     = wireguard_asymmetric_key.nat[0].private_key
    destination = "/tmp/wg_privatekey"
  }

  provisioner "file" {
    content     = <<-WGCONF
      [Interface]
      Address = ${var.poc_hybrid_wireguard_nat_tunnel_ip}/30
      ListenPort = ${var.poc_hybrid_wireguard_port}
      PrivateKey = ${wireguard_asymmetric_key.nat[0].private_key}

      [Peer]
      PublicKey = ${trimspace(wireguard_asymmetric_key.aws[0].public_key)}
      Endpoint = ${aws_instance.poc_hybrid_external_node[0].public_ip}:${var.poc_hybrid_wireguard_port}
      AllowedIPs = ${var.poc_hybrid_aws_vpc_cidr},${var.poc_hybrid_wireguard_tunnel_cidr}
      PersistentKeepalive = 25
    WGCONF
    destination = "/tmp/wg0.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eux pipefail",
      "sudo apt install -y wireguard-tools",
      "modprobe wireguard || true",
      "sudo mkdir -p /etc/wireguard && sudo chmod 700 /etc/wireguard",
      "sudo install -m 600 /tmp/wg_privatekey /etc/wireguard/privatekey",
      "sudo install -m 600 /tmp/wg0.conf /etc/wireguard/wg0.conf",
      "rm -f /tmp/wg_privatekey /tmp/wg0.conf",
      "sudo systemctl enable --now wg-quick@wg0",
      "sudo ip route replace ${var.poc_hybrid_aws_vpc_cidr} dev wg0 || true",
    ]
  }

  depends_on = [
    terraform_data.nat_router_await_cloud_init,
  ]
}
