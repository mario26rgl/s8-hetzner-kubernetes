locals {
  ssh_agent_identity = var.ssh_agent_identity

  # the hosts name with its unique suffix attached
  name = "${var.name}-${random_string.server.id}"

  # check if the user has set dns servers
  has_dns_servers = length(var.dns_servers) > 0
}
