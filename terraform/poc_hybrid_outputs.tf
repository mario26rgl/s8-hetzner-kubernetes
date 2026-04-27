output "aws_vpc_info" {
  description = "Comprehensive AWS VPC information for the hybrid PoC."
  value = {
    id   = try(aws_vpc.poc_hybrid[0].id, null)
    cidr = try(aws_vpc.poc_hybrid[0].cidr_block, null)
  }
}

output "aws_public_subnet_info" {
  description = "Public subnet ID hosting the hybrid external node."
  value = {
    id   = try(aws_subnet.poc_hybrid_public[0].id, null)
    cidr = try(aws_subnet.poc_hybrid_public[0].cidr_block, null)
  }
}

output "aws_node_info" {
  description = "Details of the AWS external node instance."
  value = {
    id            = try(aws_instance.poc_hybrid_external_node[0].id, null)
    private_ip    = try(aws_instance.poc_hybrid_external_node[0].private_ip, null)
    public_ip     = try(aws_instance.poc_hybrid_external_node[0].public_ip, null)
    instance_type = try(aws_instance.poc_hybrid_external_node[0].instance_type, null)
  }
}

output "poc_hybrid_wireguard_tunnel_ips" {
  description = "Tunnel endpoint IP assignments for NAT and AWS peers."
  value = {
    nat = var.poc_hybrid_wireguard_nat_tunnel_ip
    aws = var.poc_hybrid_wireguard_aws_tunnel_ip
  }
}