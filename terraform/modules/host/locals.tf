locals {
  ssh_agent_identity = var.ssh_agent_identity

  # the hosts name with its unique suffix attached
  name = var.k3s_masquerade_as_aws_nodes ? format("i-%s", substr(sha1("${var.name}-${random_string.server.id}"), 0, 17)) : "${var.name}-${random_string.server.id}"

  # check if the user has set dns servers
  has_dns_servers = length(var.dns_servers) > 0
}
