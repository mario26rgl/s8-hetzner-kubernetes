locals {
  dns_enabled = var.dns_zone != ""
  # DNS records are only created when using an external Hetzner LB (not klipper).
  dns_lb_enabled = local.dns_enabled && var.ingress_controller != "none" && !local.using_klipper_lb
}

# Look up the DNS zone that was created in Hetzner DNS Console
data "hcloud_zone" "main" {
  count = local.dns_enabled ? 1 : 0
  name  = var.dns_zone
}

# Look up the Traefik ingress LB by the fixed name assigned to it by the
# Hetzner CCM (load-balancer.hetzner.cloud/name annotation on the Service).
data "hcloud_load_balancer" "traefik" {
  count      = local.dns_lb_enabled ? 1 : 0
  name       = local.load_balancer_name
  depends_on = [terraform_data.kustomization]
}

# Wildcard A record: every subdomain of the zone resolves to the Traefik LB.
# Traefik routes each hostname to the correct backend via Ingress rules.
resource "hcloud_zone_rrset" "wildcard" {
  count = local.dns_lb_enabled && length(data.hcloud_load_balancer.traefik) > 0 ? 1 : 0
  zone  = data.hcloud_zone.main[0].id
  name  = "*"
  type  = "A"

  ttl = 300

  labels = local.labels

  records = [
    { value = data.hcloud_load_balancer.traefik[0].ipv4, comment = "Traefik Ingress LB" },
  ]

  change_protection = false
}

# Apex A record: bare domain (s8-hetzner.online) also reaches Traefik.
resource "hcloud_zone_rrset" "apex" {
  count = local.dns_lb_enabled && length(data.hcloud_load_balancer.traefik) > 0 ? 1 : 0
  zone  = data.hcloud_zone.main[0].id
  name  = "@"
  type  = "A"

  ttl = 300

  labels = local.labels

  records = [
    { value = data.hcloud_load_balancer.traefik[0].ipv4, comment = "Traefik Ingress LB" },
  ]

  change_protection = false
}