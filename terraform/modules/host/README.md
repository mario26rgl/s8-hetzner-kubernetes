# Module `modules/host`

This module provisions a single Hetzner host (control-plane or agent) and exposes outputs used by the root module. It wraps `hcloud_server` with cloud-init, SSH key attachments, and optional post-provision actions.

## Purpose

- Provision a VM suitable for K3s control-plane or agent roles.
- Attach SSH keys and firewalls, assign private IPs from a subnet, install packages and run cloud-init/user-data.
- Expose a small set of outputs (addresses, name, id) consumed by the root module.

## Inputs (variables)

(Complete inputs are defined in `terraform/modules/host/variables.tf`. Key ones shown here.)

- `name` (string) — Host name.
- `microos_snapshot_id` (string) — ID of the MicroOS snapshot image to use.
- `ssh_port` (number) — SSH port.
- `ssh_agent_identity` (string) — SSH public key for agent identity.
- `ssh_keys` (list(string)) — Ref(s) to Hetzner SSH key IDs to attach.
- `ssh_private_key` (string, sensitive) — Private key used for remote provisioners if needed.
- `firewall_ids` (set(number)) — Firewall IDs to attach.
- `placement_group_id` (number) — Optional placement group.
- `labels` (map) — Labels applied to the server (used by LB target selectors).
- `location` (string) — Hetzner datacenter location.
- `ipv4_subnet_id` (string) — Subnet where the server gets its private IP.
- `private_ipv4` (string) — Explicit private IP assignment.
- `server_type` (string) — Hetzner flavor (e.g., `cx31`).
- `backups` (bool) — Enable Hetzner automatic backups.
- `packages_to_install` (list(string)) — Extra packages installed via cloud-init.
- `k3s_registries`, `k3s_kubelet_config`, `k3s_audit_policy_config` — strings used to configure k3s/kubelet/audit policies via cloud-init templates.
- `cloudinit_write_files_common`, `cloudinit_runcmd_common` — fragments merged into the node's cloud-init payload.
- `swap_size`, `zram_size` — optional swap/zram sizing.
- `network_id` (number) — network to attach to.
- `ssh_bastion` (object) — info to route remote-exec via a bastion (host, port, user, private key).
- `k3s_masquerade_as_aws_nodes` (bool) — when true generate EC2-like provider ids for k3s nodes.

## Outputs (see `terraform/modules/host/out.tf`)

- `ipv4_address` — Public IPv4 address of the server (if public_net enabled).
- `ipv6_address` — Public IPv6 address (if available).
- `private_ipv4_address` — Private IP inside the Hetzner network/subnet.
- `name` — Server resource name.
- `id` — Hetzner server ID.
- `domain_assignments` — (placeholder) domain assignment mapping for primary IP.

## What the module does (summary)

- Creates `hcloud_server.server` with the provided `image`/`server_type` and network attachments.
- Attaches provided SSH key IDs and optionally writes additional SSH public keys to `authorized_keys` via cloud-init.
- Writes cloud-init payload (files + runcmd) combining common fragments and node-specific k3s configuration.
- Exposes server addresses and IDs as outputs for higher-level modules to assemble LB targets and provisioners.
