module "values_merger_cilium" {
  source          = "./modules/values_merger"
  default_values  = local.cilium_values_default
  override_values = var.cilium_values
  merge_values    = var.cilium_merge_values
}

module "values_merger_hetzner_ccm" {
  source          = "./modules/values_merger"
  default_values  = local.hetzner_ccm_values_default
  override_values = var.hetzner_ccm_values
  merge_values    = var.hetzner_ccm_merge_values
}

module "values_merger_hetzner_csi" {
  source          = "./modules/values_merger"
  default_values  = local.hetzner_csi_values_default
  override_values = var.hetzner_csi_values
  merge_values    = var.hetzner_csi_merge_values
}

module "values_merger_traefik" {
  source          = "./modules/values_merger"
  default_values  = local.traefik_values_default
  override_values = var.traefik_values
  merge_values    = var.traefik_merge_values
}

module "values_merger_cert_manager" {
  source          = "./modules/values_merger"
  default_values  = local.cert_manager_values_default
  override_values = var.cert_manager_values
  merge_values    = var.cert_manager_merge_values
}

module "values_merger_argocd" {
  source          = "./modules/values_merger"
  default_values  = local.argocd_values_default
  override_values = var.argocd_values
  merge_values    = var.argocd_merge_values
}
