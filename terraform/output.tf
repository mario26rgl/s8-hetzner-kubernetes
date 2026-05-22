output "cluster_name" {
  value       = var.cluster_name
  description = "Shared suffix for all resources belonging to this cluster."
}

output "network_id" {
  value       = hcloud_network.k3s.id
  description = "The ID of the HCloud network."
}

output "control_planes_private_ipv4" {
  value       = [for obj in module.control_planes : obj.private_ipv4_address]
  description = "The private IPv4 addresses of the controlplane servers."
}

output "agents_private_ipv4" {
  value       = [for obj in module.agents : obj.private_ipv4_address]
  description = "The private IPv4 addresses of the agent servers."
}

output "ingress_public_ipv4" {
  description = "The public IPv4 address of the Hetzner ingress load balancer"
  value       = try(hcloud_load_balancer.cluster[0].ipv4, null)
}

output "nat_public_ipv4" {
  description = "The public IPv4 address of the Hetzner NAT router (bastion)"
  value       = try(hcloud_primary_ip.nat_router_primary_ipv4[0].ip_address, null)
}

output "k3s_endpoint" {
  description = "A controller endpoint to register new nodes"
  value       = local.k3s_endpoint
}

output "kubeconfig" {
  value       = local.kubeconfig_external
  description = "Kubeconfig file content with external IP address"
  sensitive   = true
}

output "kubeconfig_data" {
  description = "Structured kubeconfig data to supply to other providers"
  value       = local.kubeconfig_data
  sensitive   = true
}

output "nat_private_ipv4" {
  description = "The private IPv4 address of the NAT router (bastion)."
  value       = local.nat_gateway_ip
}

output "token" {
  description = "The token to join the cluster, used for both control plane and agent nodes."
  value       = random_password.k3s_token.result
  sensitive   = true
}
