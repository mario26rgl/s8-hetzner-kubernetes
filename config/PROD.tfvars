ssh_public_key                           = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM7TU6VAnJfg6W7S/1BOvdNoR5YuMSVCrthMMZ8n/9bi k3s-hetzner"
network_region                           = "eu-central"
network_ipv4_cidr                        = "10.0.0.0/8"
use_control_plane_lb                     = true
control_plane_lb_enable_public_interface = false # Forward cluster API traffic through Bastion
automatically_upgrade_os                 = false # Development environment
cluster_name                             = "s8-hetzner"
cni_plugin                               = "cilium"
disable_kube_proxy                       = true # We use Cilium
load_balancer_location                   = "hel1"
load_balancer_type                       = "lb11"
load_balancer_algorithm_type             = "round_robin"
allow_scheduling_on_control_plane        = false
enable_metrics_server                    = true
cluster_ipv4_cidr                        = "10.42.0.0/16"
service_ipv4_cidr                        = "10.43.0.0/16"
enable_argocd                            = true
argocd_ingress_hostname                  = "argocd.s8-hetzner.online"
enable_cert_manager                      = true
acme_email                               = "mario_constantin1234@proton.me"
issuer_environment                       = "staging"

# MUST BE ODD NUMBER
control_plane_nodepools = [
  {
    name        = "control-plane-nbg1",
    server_type = "cx33",
    location    = "hel1",
    labels      = [],
    taints      = [],
    count       = 1

    # Optimization - prevent OOM kills
    zram_size = "1G"

    # To disable public ips (default: false)
    disable_ipv4 = true
    disable_ipv6 = true
  },
  ### HA - Cross-region control plane
  # {
  #     name        = "control-plane-hel1",
  #     server_type = "cx23",
  #     location    = "fsn1",
  #     labels      = [],
  #     taints      = [],
  #     count       = 1

  #     # Optimization - prevent OOM kills
  #     zram_size   = "1G"
  #     kubelet_args = ["kube-reserved=cpu=250m,memory=1500Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"]

  #     # To disable public ips (default: false)
  #     disable_ipv4 = true
  #     disable_ipv6 = true
  # }
]

agent_nodepools = [
  {
    name         = "agent-helsinki",
    server_type  = "cx23",
    location     = "hel1",
    labels       = [],
    taints       = [],
    count        = 1
    zram_size    = "1G"
    kubelet_args = ["kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"]

    # disable public ips (default: false)
    disable_ipv4 = true
    disable_ipv6 = true
  },
  ## HA - Cross-region worker nodes
  # {
  #   name        = "agent-falkenstein",
  #   server_type = "cx23",
  #   location    = "fsn1",
  #   labels      = [],
  #   taints      = [],
  #   count       = 0
  #   zram_size   = "1G"
  #   kubelet_args = ["kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"]

  #   # disable public ips (default: false)
  #   disable_ipv4 = true
  #   disable_ipv6 = true
  # },
  ## Migration to larger instance type
  # {
  #   name        = "agent-large",
  #   server_type = "cx33",
  #   location    = "hel1",
  #   labels      = [],
  #   taints      = [],
  #   count       = 0
  #   subnet_ip_range = "10.100.0.0/16"
  # },
]

autoscaler_nodepools = [
  {
    name        = "agent-autoscaler",
    server_type = "cx23",
    location    = "hel1",
    min_nodes   = 0
    max_nodes   = 1
    labels = {
      "k8s.io/provisioning-strategy" = "cluster-autoscaler"
    }
    count     = 0
    zram_size = "1G"
  }
]

nat_router = {
  server_type = "cx23"
  location    = "hel1"
  labels      = {}
}