output "cluster_name" {
  value       = var.cluster_name
  description = "Shared suffix for all resources belonging to this cluster."
}

output "network_id" {
  value       = hcloud_network.k3s.id
  description = "The ID of the HCloud network."
}

output "ssh_key_id" {
  value       = local.hcloud_ssh_key_id
  description = "The ID of the HCloud SSH key."
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

output "k3s_endpoint" {
  description = "A controller endpoint to register new nodes"
  value       = local.k3s_endpoint
}

output "k3s_token" {
  description = "The k3s token to register new nodes"
  value       = local.k3s_token
  sensitive   = true
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

output "nat_router_public_ipv4" {
  description = "The public IPv4 address of the NAT router (bastion)."
  value       = try(hcloud_server.nat_router[0].ipv4_address, null)
}

output "cilium_values" {
  description = "Helm values.yaml used for Cilium"
  value       = local.cilium_values
  sensitive   = true
}

output "traefik_values" {
  description = "Helm values.yaml used for Traefik"
  value       = local.traefik_values
  sensitive   = true
}

output "hetzner_ccm_values" {
  description = "Helm values.yaml used for Hetzner CCM"
  value       = local.hetzner_ccm_values
  sensitive   = true
}

output "hetzner_csi_values" {
  description = "Helm values.yaml used for Hetzner CSI"
  value       = local.hetzner_csi_values
  sensitive   = true
}

output "cert_manager_values" {
  description = "Helm values.yaml used for cert-manager"
  value       = local.cert_manager_values
  sensitive   = true
}
