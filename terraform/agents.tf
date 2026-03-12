module "agents" {
  source = "./modules/host"

  providers = {
    hcloud = hcloud,
  }

  for_each = local.agent_nodes

  name                             = "${var.cluster_name}-${each.value.nodepool_name}${try(each.value.node_name_suffix, "")}"
  microos_snapshot_id              = data.hcloud_image.microos_x86_snapshot.id
  ssh_port                         = var.ssh_port
  ssh_agent_identity               = var.ssh_public_key
  ssh_additional_public_keys       = var.ssh_additional_public_keys
  placement_group_id               = null
  location                         = each.value.location
  server_type                      = each.value.server_type
  backups                          = each.value.backups
  ipv4_subnet_id                   = hcloud_network_subnet.agent[[for i, v in var.agent_nodepools : i if v.name == each.value.nodepool_name][0]].id
  dns_servers                      = var.dns_servers
  k3s_registries                   = var.k3s_registries
  k3s_registries_update_script     = local.k3s_registries_update_script
  cloudinit_write_files_common     = local.cloudinit_write_files_common
  k3s_kubelet_config               = var.k3s_kubelet_config
  k3s_kubelet_config_update_script = local.k3s_kubelet_config_update_script
  k3s_audit_policy_config          = ""
  k3s_audit_policy_update_script   = ""
  cloudinit_runcmd_common          = local.cloudinit_runcmd_common
  swap_size                        = each.value.swap_size
  zram_size                        = each.value.zram_size
  keep_disk_size                   = var.keep_disk_agents
  disable_ipv4                     = each.value.disable_ipv4
  disable_ipv6                     = each.value.disable_ipv6
  ssh_bastion                      = local.ssh_bastion
  network_id                       = hcloud_network.k3s.id
  private_ipv4                     = cidrhost(hcloud_network_subnet.agent[[for i, v in var.agent_nodepools : i if v.name == each.value.nodepool_name][0]].ip_range, each.value.index + (local.network_size >= 16 ? 101 : floor(pow(local.subnet_size, 2) * 0.4)))

  labels = merge(local.labels, local.labels_agent_node)

  automatically_upgrade_os = var.automatically_upgrade_os

  network_gw_ipv4 = local.network_gw_ipv4

  depends_on = [
    hcloud_network_subnet.agent,
    hcloud_server.nat_router,
    terraform_data.nat_router_await_cloud_init,
  ]
}

locals {
  k3s-agent-config = { for k, v in local.agent_nodes : k => merge(
    {
      node-name = module.agents[k].name
      server    = local.k3s_endpoint
      token     = local.k3s_token
      # Kubelet arg precedence (first wins): local.kubelet_arg > v.kubelet_args > k3s_global_kubelet_args > k3s_agent_kubelet_args
      kubelet-arg = concat(
        local.kubelet_arg,
        v.kubelet_args,
        var.k3s_global_kubelet_args,
        var.k3s_agent_kubelet_args
      )
      flannel-iface = local.flannel_iface
      node-ip       = module.agents[k].private_ipv4_address
      node-label    = v.labels
      node-taint    = v.taints
    },
    var.agent_nodes_custom_config,
    local.prefer_bundled_bin_config,
    # Force selinux=false if disable_selinux = true.
    var.disable_selinux
    ? { selinux = false }
    : (v.selinux == true ? { selinux = true } : {})
  ) }

  agent_ips = {
    for k, v in module.agents : k => coalesce(
      v.ipv4_address,
      v.ipv6_address,
      v.private_ipv4_address
    )
  }
}

resource "terraform_data" "agent_config" {
  for_each = local.agent_nodes

  triggers_replace = {
    agent_id = module.agents[each.key].id
    config   = sha1(yamlencode(local.k3s-agent-config[each.key]))
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.agent_ips[each.key]
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  # Generating k3s agent config file
  provisioner "file" {
    content     = yamlencode(local.k3s-agent-config[each.key])
    destination = "/tmp/config.yaml"
  }

  provisioner "remote-exec" {
    inline = [local.k3s_config_update_script]
  }
}

resource "terraform_data" "agents" {
  for_each = local.agent_nodes

  triggers_replace = {
    agent_id = module.agents[each.key].id
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.agent_ips[each.key]
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  # Install k3s agent
  provisioner "remote-exec" {
    inline = local.install_k3s_agent
  }

  # Start the k3s agent and wait for it to have started
  provisioner "remote-exec" {
    inline = concat([
      "timeout 120 systemctl start k3s-agent 2> /dev/null",
      <<-EOT
      timeout 120 bash <<EOF
        until systemctl status k3s-agent > /dev/null; do
          systemctl start k3s-agent 2> /dev/null
          echo "Waiting for the k3s agent to start..."
          sleep 2
        done
      EOF
      EOT
    ])
  }

  depends_on = [
    terraform_data.first_control_plane,
    terraform_data.agent_config,
    hcloud_network_subnet.agent
  ]
}
