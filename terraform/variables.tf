variable "hcloud_token" {
  description = "Hetzner Cloud API Token."
  type        = string
  sensitive   = true
}

variable "ssh_port" {
  description = "The main SSH port to connect to the nodes."
  type        = number
  default     = 22

  validation {
    condition     = var.ssh_port >= 0 && var.ssh_port <= 65535
    error_message = "The SSH port must use a valid range from 0 to 65535."
  }
}

variable "ssh_public_key" {
  description = "SSH public Key."
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private Key."
  type        = string
  sensitive   = true
  default     = null
}

variable "ssh_hcloud_key_label" {
  description = "Additional SSH public Keys by hcloud label. e.g. role=admin"
  type        = string
  default     = ""
}

variable "ssh_additional_public_keys" {
  description = "Additional SSH public Keys. Use them to grant other team members root access to your cluster nodes."
  type        = list(string)
  default     = []
}

variable "authentication_config" {
  description = "Structured authentication configuration. This can be used to define external authentication providers."
  type        = string
  default     = ""
}

variable "hcloud_ssh_key_id" {
  description = "If passed, a key already registered within hetzner is used. Otherwise, a new one will be created by the module."
  type        = string
  default     = null
}

variable "ssh_max_auth_tries" {
  description = "The maximum number of authentication attempts permitted per connection."
  type        = number
  default     = 2
}

variable "network_region" {
  description = "Default region for network."
  type        = string
  default     = "eu-central"
}
variable "network_ipv4_cidr" {
  description = "The main network cidr that all subnets will be created upon."
  type        = string
  default     = "10.0.0.0/8"
}

variable "subnet_amount" {
  description = "The amount of subnets into which the network will be split. Must be a power of 2."
  type        = number
  default     = 256
  validation {
    condition     = floor(log(var.subnet_amount, 2)) == log(var.subnet_amount, 2)
    error_message = "Subnet amount must be a power of 2."
  }
  validation {
    # Host bits = 32 - prefix, must have enough bits to create subnet_amount subnets
    condition     = pow(2, 32 - tonumber(split("/", var.network_ipv4_cidr)[1])) >= var.subnet_amount
    error_message = "The network CIDR is too small for the requested subnet amount. Reduce subnet_amount or use a larger network."
  }
  validation {
    condition     = var.subnet_amount >= length(var.control_plane_nodepools) + length(var.agent_nodepools) + (var.nat_router == null ? 0 : (var.nat_router.enable_redundancy == false ? 1 : 2))
    error_message = "Subnet amount must be large enough so that a subnet for each agent pool, each control plane pool and (if enabled) the nat router can be created in the network."
  }
}

variable "cluster_ipv4_cidr" {
  description = "Internal Pod CIDR, used for the controller and currently for cilium."
  type        = string
  default     = "10.42.0.0/16"
}

variable "service_ipv4_cidr" {
  description = "Internal Service CIDR, used for the controller and currently for cilium."
  type        = string
  default     = "10.43.0.0/16"
}

variable "cluster_dns_ipv4" {
  description = "Internal Service IPv4 address of core-dns."
  type        = string
  default     = null
}


variable "nat_router" {
  description = "Do you want to pipe all egress through a single nat router which is to be constructed? Note: Requires use_control_plane_lb=true when enabled. Automatically forwards port 6443 to the control plane LB when control_plane_lb_enable_public_interface=false."
  nullable    = true
  default     = null
  type = object({
    server_type       = string
    location          = string
    labels            = optional(map(string), {})
    enable_sudo       = optional(bool, false)
    enable_redundancy = optional(bool, false)
    standby_location  = optional(string, "")
  })

  validation {
    condition     = var.nat_router == null || !var.nat_router.enable_redundancy || var.nat_router.standby_location != ""
    error_message = "When nat_router.enable_redundancy is true, standby_location must be provided."
  }
}

variable "nat_router_subnet_index" {
  type        = number
  default     = 200
  description = "Subnet index for NAT router. Default 200 is safe for most deployments. Must not conflict with control plane (counting down from 255) or agent pools (counting up from 0)."

  validation {
    condition     = var.nat_router_subnet_index >= 0 && var.nat_router_subnet_index < var.subnet_amount
    error_message = "NAT router subnet index must be between 0 and subnet_amount."
  }
}

variable "load_balancer_location" {
  description = "Default load balancer location."
  type        = string
  default     = "nbg1"
}

variable "load_balancer_type" {
  description = "Default load balancer server type."
  type        = string
  default     = "lb11"
}

variable "load_balancer_disable_ipv6" {
  description = "Disable IPv6 for the load balancer."
  type        = bool
  default     = false
}

variable "load_balancer_disable_public_network" {
  description = "Disables the public network of the load balancer."
  type        = bool
  default     = false
}

variable "load_balancer_algorithm_type" {
  description = "Specifies the algorithm type of the load balancer."
  type        = string
  default     = "round_robin"
}

variable "load_balancer_health_check_interval" {
  description = "Specifies the interval at which a health check is performed. Minimum is 3s."
  type        = string
  default     = "15s"
}

variable "load_balancer_health_check_timeout" {
  description = "Specifies the timeout of a single health check. Must not be greater than the health check interval. Minimum is 1s."
  type        = string
  default     = "10s"
}

variable "load_balancer_health_check_retries" {
  description = "Specifies the number of times a health check is retried before a target is marked as unhealthy."
  type        = number
  default     = 3
}

variable "exclude_agents_from_external_load_balancers" {
  description = "Add node.kubernetes.io/exclude-from-external-load-balancers=true label to agent nodes. Enable this if you use both the Terraform-managed ingress LB and CCM-managed LoadBalancer services, and want to prevent double-registration of agents to the CCM LBs. Note: This excludes agents from ALL CCM-managed LoadBalancer services, not just ingress."
  type        = bool
  default     = false
}

# ================================
# Control Plane nodepool Configuration

variable "control_plane_nodepools" {
  description = "Number of control plane nodes."
  type = list(object({
    name         = string
    server_type  = string
    location     = string
    backups      = optional(bool)
    labels       = list(string)
    taints       = list(string)
    count        = number
    swap_size    = optional(string, "")
    zram_size    = optional(string, "")
    kubelet_args = optional(list(string), ["kube-reserved=cpu=250m,memory=1500Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"])
    selinux      = optional(bool, true)
    disable_ipv4 = optional(bool, false)
    disable_ipv6 = optional(bool, false)
    network_id   = optional(number, 0)
  }))
  default = []
  validation {
    condition = length(
      [for control_plane_nodepool in var.control_plane_nodepools : control_plane_nodepool.name]
      ) == length(
      distinct(
        [for control_plane_nodepool in var.control_plane_nodepools : control_plane_nodepool.name]
      )
    )
    error_message = "Names in control_plane_nodepools must be unique."
  }
  validation {
    condition     = length(var.control_plane_nodepools) > 0
    error_message = "At least one control plane nodepool is required. Kubernetes cannot run without control plane nodes."
  }
  validation {
    condition     = length(var.control_plane_nodepools) == 0 || sum([for v in var.control_plane_nodepools : v.count]) >= 1
    error_message = "At least one control plane node is required (total count across all control_plane_nodepools must be >= 1)."
  }
}

# ================================
# Static nodepool Configuration

variable "agent_nodepools" {
  description = "Number of agent nodes."
  type = list(object({
    name            = string
    server_type     = string
    location        = string
    backups         = optional(bool)
    labels          = list(string)
    taints          = list(string)
    swap_size       = optional(string, "")
    zram_size       = optional(string, "")
    kubelet_args    = optional(list(string), ["kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"])
    selinux         = optional(bool, true)
    subnet_ip_range = optional(string, null)
    count           = optional(number, null)
    disable_ipv4    = optional(bool, false)
    disable_ipv6    = optional(bool, false)
    network_id      = optional(number, 0)
    nodes = optional(map(object({
      server_type               = optional(string)
      location                  = optional(string)
      backups                   = optional(bool)
      labels                    = optional(list(string))
      taints                    = optional(list(string))
      swap_size                 = optional(string, "")
      zram_size                 = optional(string, "")
      kubelet_args              = optional(list(string), ["kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"])
      selinux                   = optional(bool, true)
      append_index_to_node_name = optional(bool, true)
    })))
  }))
  default = []

  validation {
    condition = length(
      [for agent_nodepool in var.agent_nodepools : agent_nodepool.name]
      ) == length(
      distinct(
        [for agent_nodepool in var.agent_nodepools : agent_nodepool.name]
      )
    )
    error_message = "Names in agent_nodepools must be unique."
  }

  validation {
    condition     = alltrue([for agent_nodepool in var.agent_nodepools : (agent_nodepool.count == null) != (agent_nodepool.nodes == null)])
    error_message = "Set either nodes or count per agent_nodepool, not both."
  }


  validation {
    condition = alltrue([for agent_nodepool in var.agent_nodepools :
      alltrue([for agent_key, agent_node in coalesce(agent_nodepool.nodes, {}) : can(tonumber(agent_key)) && tonumber(agent_key) == floor(tonumber(agent_key)) && 0 <= tonumber(agent_key) && tonumber(agent_key) < 154])
    ])
    # 154 because the private ip is derived from tonumber(key) + 101. See private_ipv4 in agents.tf
    error_message = "The key for each individual node in a nodepool must be a stable integer in the range [0, 153] cast as a string."
  }

  validation {
    condition = length(var.agent_nodepools) == 0 ? true : sum([for agent_nodepool in var.agent_nodepools : length(coalesce(agent_nodepool.nodes, {})) + coalesce(agent_nodepool.count, 0)]) <= 100
    # 154 because the private ip is derived from tonumber(key) + 101. See private_ipv4 in agents.tf
    error_message = "Hetzner does not support networks with more than 100 servers."
  }


}

# ================================
# Cluster Autoscaler Configuration

variable "cluster_autoscaler_config" {
  description = "Cluster autoscaler configuration"
  type = object({
    image           = string
    image_tag       = string
    replicas        = number
    extra_args      = list(string)
    disable_ipv4    = bool
    disable_ipv6    = bool
    resource_limits = bool
    resource_values = object({
      requests = object({
        cpu    = string
        memory = string
      })
      limits = object({
        cpu    = string
        memory = string
      })
    })
    stderr_threshold = string
    log_level        = number
    log_to_stderr    = bool
    timeout_minutes  = number
  })
  default = {
    image           = "registry.k8s.io/autoscaling/cluster-autoscaler"
    image_tag       = "v1.33.3"
    replicas        = 1
    extra_args      = []
    disable_ipv4    = false
    disable_ipv6    = false
    resource_limits = true
    resource_values = {
      requests = {
        cpu    = "100m"
        memory = "300Mi"
      }
      limits = {
        cpu    = "100m"
        memory = "300Mi"
      }
    }
    stderr_threshold = "INFO"
    log_level        = 4
    log_to_stderr    = true
    timeout_minutes  = 15
  }

  validation {
    condition     = var.cluster_autoscaler_config.log_level >= 0 && var.cluster_autoscaler_config.log_level <= 5
    error_message = "The log level must be between 0 and 5."
  }
}

variable "autoscaler_subnet_index" {
  description = "Optional agent subnet index for autoscaled nodes. If null, defaults to the first agent subnet (or control-plane subnet if no agent subnet exists)."
  type        = number
  default     = null

  validation {
    condition = var.autoscaler_subnet_index == null || (
      var.autoscaler_subnet_index >= 0 &&
      var.autoscaler_subnet_index < length(var.agent_nodepools)
    )
    error_message = "autoscaler_subnet_index must be null or a valid agent nodepool index."
  }
}

variable "autoscaler_nodepools" {
  description = "Cluster autoscaler nodepools."
  type = list(object({
    name         = string
    server_type  = string
    location     = string
    min_nodes    = number
    max_nodes    = number
    labels       = optional(map(string), {})
    kubelet_args = optional(list(string), ["kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"])
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    swap_size = optional(string, "")
    zram_size = optional(string, "")
  }))
  default = []
}


variable "hetzner_ccm_version" {
  type        = string
  default     = null
  description = "Version of Kubernetes Cloud Controller Manager for Hetzner Cloud. See https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases for the available versions."
}

variable "hetzner_ccm_use_helm" {
  type        = bool
  default     = true
  description = "Whether to use the helm chart for the Hetzner CCM."
}

variable "hetzner_csi_version" {
  type        = string
  default     = null
  description = "Version of Container Storage Interface driver for Hetzner Cloud. See https://github.com/hetznercloud/csi-driver/releases for the available versions."
}

variable "hetzner_csi_values" {
  type        = string
  default     = ""
  description = "Additional helm values file to pass to hetzner csi as 'valuesContent' at the HelmChart."
}

variable "hetzner_csi_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or hetzner_csi_values if set). User values take precedence. Requires valid YAML format."
}


variable "restrict_outbound_traffic" {
  type        = bool
  default     = true
  description = "Whether or not to restrict the outbound traffic."
}

variable "enable_klipper_metal_lb" {
  type        = bool
  default     = false
  description = "Use klipper load balancer."
}

variable "etcd_s3_backup" {
  description = "Etcd cluster state backup to S3 storage"
  type        = map(any)
  sensitive   = true
  default     = {}
}

variable "ingress_controller" {
  type        = string
  default     = "traefik"
  description = "The name of the ingress controller."

  validation {
    condition     = contains(["traefik", "none"], var.ingress_controller)
    error_message = "Must be one of \"traefik\" or \"none\""
  }
}

variable "ingress_replica_count" {
  type        = number
  default     = 0
  description = "Number of replicas per ingress controller. 0 means autodetect based on the number of agent nodes."

  validation {
    condition     = var.ingress_replica_count >= 0
    error_message = "Number of ingress replicas can't be below 0."
  }
}

variable "ingress_max_replica_count" {
  type        = number
  default     = 10
  description = "Number of maximum replicas per ingress controller. Used for ingress HPA. Must be higher than number of replicas."

  validation {
    condition     = var.ingress_max_replica_count >= 0
    error_message = "Number of ingress maximum replicas can't be below 0."
  }
}

variable "traefik_image_tag" {
  type        = string
  default     = ""
  description = "Traefik image tag. Useful to use the beta version for new features. Example: v3.0.0-beta5"
}

variable "traefik_autoscaling" {
  type        = bool
  default     = true
  description = "Should traefik enable Horizontal Pod Autoscaler."
}

variable "traefik_redirect_to_https" {
  type        = bool
  default     = true
  description = "Should traefik redirect http traffic to https."
}

variable "traefik_pod_disruption_budget" {
  type        = bool
  default     = true
  description = "Should traefik enable pod disruption budget. Default values are maxUnavailable: 33% and minAvailable: 1."
}

variable "traefik_provider_kubernetes_gateway_enabled" {
  type        = bool
  default     = false
  description = "Should traefik enable the kubernetes gateway provider. Default is false."
}

variable "traefik_resource_limits" {
  type        = bool
  default     = true
  description = "Should traefik enable default resource requests and limits. Default values are requests: 100m & 50Mi and limits: 300m & 150Mi."
}

variable "traefik_resource_values" {
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      memory = "50Mi"
      cpu    = "100m"
    }
    limits = {
      memory = "150Mi"
      cpu    = "300m"
    }
  }
  description = "Requests and limits for Traefik."
}

variable "traefik_additional_ports" {
  type = list(object({
    name        = string
    port        = number
    exposedPort = number
  }))
  default     = []
  description = "Additional ports to pass to Traefik. These are the ones that go into the ports section of the Traefik helm values file."
}

variable "traefik_additional_options" {
  type        = list(string)
  default     = []
  description = "Additional options to pass to Traefik as a list of strings. These are the ones that go into the additionalArguments section of the Traefik helm values file."
}

variable "traefik_additional_trusted_ips" {
  type        = list(string)
  default     = []
  description = "Additional Trusted IPs to pass to Traefik. These are the ones that go into the trustedIPs section of the Traefik helm values file."
}

variable "traefik_version" {
  type        = string
  default     = ""
  description = "Version of Traefik helm chart. See https://github.com/traefik/traefik-helm-chart/releases for the available versions."
}

variable "traefik_values" {
  type        = string
  default     = ""
  description = "Additional helm values file to pass to Traefik as 'valuesContent' at the HelmChart."
}

variable "traefik_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or traefik_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.traefik_merge_values == "" || can(yamldecode(var.traefik_merge_values))
    error_message = "traefik_merge_values must be valid YAML format or empty string."
  }
}

variable "allow_scheduling_on_control_plane" {
  type        = bool
  default     = false
  description = "Whether to allow non-control-plane workloads to run on the control-plane nodes."
}

variable "enable_metrics_server" {
  type        = bool
  default     = true
  description = "Whether to enable or disable k3s metric server."
}

variable "initial_k3s_channel" {
  type        = string
  default     = "v1.33" # Please update kube.tf.example too when changing this variable
  description = "Allows you to specify an initial k3s channel. See https://update.k3s.io/v1-release/channels for available channels."

  validation {
    condition     = contains(["stable", "latest", "testing", "v1.16", "v1.17", "v1.18", "v1.19", "v1.20", "v1.21", "v1.22", "v1.23", "v1.24", "v1.25", "v1.26", "v1.27", "v1.28", "v1.29", "v1.30", "v1.31", "v1.32", "v1.33", "v1.34", "v1.35"], var.initial_k3s_channel)
    error_message = "The initial k3s channel must be one of stable, latest or testing, or any of the minor kube versions like v1.26."
  }
}

variable "install_k3s_version" {
  type        = string
  default     = ""
  description = "Allows you to specify the k3s version (Example: v1.29.6+k3s2). Supersedes initial_k3s_channel. See https://github.com/k3s-io/k3s/releases for available versions."
}

variable "system_upgrade_enable_eviction" {
  type        = bool
  default     = true
  description = "Whether to directly delete pods during system upgrade (k3s) or evict them. Defaults to true. Disable this on small clusters to avoid system upgrades hanging since pods resisting eviction keep node unschedulable forever. NOTE: turning this off, introduces potential downtime of services of the upgraded nodes."
}

variable "system_upgrade_use_drain" {
  type        = bool
  default     = true
  description = "Wether using drain (true, the default), which will deletes and transfers all pods to other nodes before a node is being upgraded, or cordon (false), which just prevents schedulung new pods on the node during upgrade and keeps all pods running"
}

variable "automatically_upgrade_k3s" {
  type        = bool
  default     = true
  description = "Whether to automatically upgrade k3s based on the selected channel."
}

variable "system_upgrade_schedule_window" {
  type = object({
    days      = optional(list(string), [])
    startTime = optional(string, "")
    endTime   = optional(string, "")
    timeZone  = optional(string, "UTC")
  })
  default     = null
  description = "Schedule window for k3s automated upgrades (system-upgrade-controller v0.15.0+). When set, upgrade jobs will only be created within the specified time window. 'days' accepts lowercase day names (e.g. [\"monday\",\"tuesday\"]). 'startTime'/'endTime' use HH:MM format. 'timeZone' defaults to UTC. See https://docs.k3s.io/upgrades/automated#scheduling-upgrades"

  validation {
    condition = var.system_upgrade_schedule_window == null ? true : (
      length(try(var.system_upgrade_schedule_window.days, [])) > 0 ||
      coalesce(try(var.system_upgrade_schedule_window.startTime, ""), "") != "" ||
      coalesce(try(var.system_upgrade_schedule_window.endTime, ""), "") != ""
    )
    error_message = "system_upgrade_schedule_window must have at least one of 'days', 'startTime', or 'endTime' set when not null."
  }

  validation {
    condition = var.system_upgrade_schedule_window == null ? true : alltrue([
      for day in try(var.system_upgrade_schedule_window.days, []) :
      can(regex("^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)$", day))
    ])
    error_message = "system_upgrade_schedule_window.days must contain lowercase day names (monday-sunday)."
  }

  validation {
    condition = var.system_upgrade_schedule_window == null ? true : alltrue([
      for time_value in [
        coalesce(try(var.system_upgrade_schedule_window.startTime, ""), ""),
        coalesce(try(var.system_upgrade_schedule_window.endTime, ""), "")
      ] :
      time_value == "" || can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", time_value))
    ])
    error_message = "system_upgrade_schedule_window.startTime and endTime must use 24-hour HH:MM format when set."
  }

  validation {
    condition = var.system_upgrade_schedule_window == null ? true : (
      coalesce(try(var.system_upgrade_schedule_window.timeZone, ""), "") == "" ||
      can(regex("^[A-Za-z_]+(?:/[A-Za-z0-9_+\\-]+)*$", coalesce(try(var.system_upgrade_schedule_window.timeZone, ""), "")))
    )
    error_message = "system_upgrade_schedule_window.timeZone must be a valid IANA timezone name (for example, UTC or Europe/Budapest)."
  }
}

variable "automatically_upgrade_os" {
  type        = bool
  default     = true
  description = "Whether to enable or disable automatic os updates. Defaults to true. Should be disabled for single-node clusters"
}

variable "extra_firewall_rules" {
  type        = list(any)
  default     = []
  description = "Additional firewall rules to apply to the cluster."
}

variable "firewall_kube_api_source" {
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
  description = "Source networks that have Kube API access to the servers."
}

variable "firewall_ssh_source" {
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
  description = "Source networks that have SSH access to the servers."
}

variable "cluster_name" {
  type        = string
  default     = "k3s"
  description = "Name of the cluster."

  validation {
    condition     = can(regex("^[a-z0-9\\-]+$", var.cluster_name))
    error_message = "The cluster name must be in the form of lowercase alphanumeric characters and/or dashes."
  }
}

variable "disable_kube_proxy" {
  type        = bool
  default     = false
  description = "Disable kube-proxy in K3s (default false)."
}

variable "cni_plugin" {
  type        = string
  default     = "cilium"
  description = "CNI plugin for k3s."

  validation {
    condition     = contains(["cilium"], var.cni_plugin)
    error_message = "The cni_plugin must be \"cilium\"."
  }
}

variable "cilium_egress_gateway_enabled" {
  type        = bool
  default     = false
  description = "Enables egress gateway to redirect and SNAT the traffic that leaves the cluster."
}

variable "cilium_hubble_enabled" {
  type        = bool
  default     = false
  description = "Enables Hubble Observability to collect and visualize network traffic."
}

variable "cilium_hubble_metrics_enabled" {
  type        = list(string)
  default     = []
  description = "Configures the list of Hubble metrics to collect"
}

variable "cilium_ipv4_native_routing_cidr" {
  type        = string
  default     = null
  description = "Used when Cilium is configured in native routing mode. The CNI assumes that the underlying network stack will forward packets to this destination without the need to apply SNAT. Default: value of \"cluster_ipv4_cidr\""
}

variable "cilium_routing_mode" {
  type        = string
  default     = "tunnel"
  description = "Set native-routing mode (\"native\") or tunneling mode (\"tunnel\")."

  validation {
    condition     = contains(["tunnel", "native"], var.cilium_routing_mode)
    error_message = "The cilium_routing_mode must be one of \"tunnel\" or \"native\"."
  }
}

variable "cilium_loadbalancer_acceleration_mode" {
  type        = string
  default     = "best-effort"
  description = "Set Cilium loadbalancer.acceleration-mode. Supported values are \"disabled\", \"native\" and \"best-effort\"."

  validation {
    condition     = contains(["disabled", "native", "best-effort"], var.cilium_loadbalancer_acceleration_mode)
    error_message = "The cilium_loadbalancer_acceleration_mode must be one of \"disabled\", \"native\" or \"best-effort\"."
  }
}

variable "cilium_values" {
  type        = string
  default     = ""
  description = "Additional helm values file to pass to Cilium as 'valuesContent' at the HelmChart."
}

variable "cilium_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or cilium_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.cilium_merge_values == "" || can(yamldecode(var.cilium_merge_values))
    error_message = "cilium_merge_values must be valid YAML format or empty string."
  }
}

variable "cilium_version" {
  type        = string
  default     = "1.17.0"
  description = "Version of Cilium. See https://github.com/cilium/cilium/releases for the available versions."
}

variable "disable_hetzner_csi" {
  type        = bool
  default     = false
  description = "Disable hetzner csi driver."
}

variable "enable_cert_manager" {
  type        = bool
  default     = true
  description = "Enable cert manager."
}

variable "cert_manager_version" {
  type        = string
  default     = "*"
  description = "Version of cert_manager."
}

variable "cert_manager_helmchart_bootstrap" {
  type        = bool
  default     = false
  description = "Whether the HelmChart cert_manager shall be run on control-plane nodes."
}

variable "cert_manager_values" {
  type        = string
  default     = ""
  description = "Additional helm values file to pass to Cert-Manager as 'valuesContent' at the HelmChart. Defaults are set in locals.tf. For cert-manager versions prior to v1.15.0, you need to set 'installCRDs: true'."
}

variable "cert_manager_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or cert_manager_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.cert_manager_merge_values == "" || can(yamldecode(var.cert_manager_merge_values))
    error_message = "cert_manager_merge_values must be valid YAML format or empty string."
  }
}

variable "lb_hostname" {
  type        = string
  default     = ""
  description = "The Hetzner Load Balancer hostname for Traefik."

  validation {
    condition     = can(regex("^(?:(?:(?:[A-Za-z0-9])|(?:[A-Za-z0-9](?:[A-Za-z0-9\\-]+)?[A-Za-z0-9]))+(\\.))+([A-Za-z]{2,})([\\/?])?([\\/?][A-Za-z0-9\\-%._~:\\/?#\\[\\]@!\\$&\\'\\(\\)\\*\\+,;=]+)?$", var.lb_hostname)) || var.lb_hostname == ""
    error_message = "It must be a valid domain name (FQDN)."
  }
}

variable "kubeconfig_server_address" {
  type        = string
  default     = ""
  description = "The hostname used for kubeconfig."
}

variable "kured_version" {
  type        = string
  default     = null
  description = "Version of Kured. See https://github.com/kubereboot/kured/releases for the available versions."
}

variable "kured_options" {
  type    = map(string)
  default = {}
}

variable "block_icmp_ping_in" {
  type        = bool
  default     = false
  description = "Block entering ICMP ping."
}

variable "use_control_plane_lb" {
  type        = bool
  default     = false
  description = "Creates a dedicated load balancer for the Kubernetes API (port 6443). When enabled, kubectl and other API clients connect through this LB instead of directly to the first control plane node. Recommended for production clusters with multiple control plane nodes for high availability. Note: This is separate from the ingress load balancer for HTTP/HTTPS traffic."
}

variable "control_plane_lb_type" {
  type        = string
  default     = "lb11"
  description = "The type of load balancer to use for the control plane load balancer. Defaults to lb11, which is the cheapest one."
}

variable "control_plane_lb_enable_public_interface" {
  type        = bool
  default     = true
  description = "Enable or disable public interface for the control plane load balancer. Defaults to true. When disabled with nat_router enabled, the NAT router automatically forwards port 6443 to the private control plane LB."
}

variable "dns_servers" {
  type = list(string)

  default = [
    "185.12.64.1",
    "185.12.64.2",
    "2a01:4ff:ff00::add:1",
  ]
  description = "IP Addresses to use for the DNS Servers, set to an empty list to use the ones provided by Hetzner. The length is limited to 3 entries, more entries is not supported by kubernetes"

  validation {
    condition     = length(var.dns_servers) <= 3
    error_message = "The list must have no more than 3 items."
  }

  validation {
    condition     = alltrue([for ip in var.dns_servers : can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", ip)) || can(regex(":", ip))])
    error_message = "Some IP addresses are incorrect."
  }
}

variable "address_for_connectivity_test" {
  description = "The address to test for external connectivity before proceeding with the installation. Defaults to Google's public DNS."
  type        = string
  default     = "8.8.8.8"
}

variable "additional_k3s_environment" {
  type        = map(any)
  default     = {}
  description = "Additional environment variables for the k3s binary. See for example https://docs.k3s.io/advanced#configuring-an-http-proxy ."
}

variable "preinstall_exec" {
  type        = list(string)
  default     = []
  description = "Additional to execute before the install calls, for example fetching and installing certs."
}

variable "postinstall_exec" {
  type        = list(string)
  default     = []
  description = "Additional to execute after the install calls, for example restoring a backup."
}

variable "create_kubeconfig" {
  type        = bool
  default     = true
  description = "Create the kubeconfig as a local file resource. Should be disabled for automatic runs."
}

variable "enable_wireguard" {
  type        = bool
  default     = false
  description = "Use wireguard-native as the backend for CNI."
}

variable "control_planes_custom_config" {
  type        = any
  default     = {}
  description = "Additional configuration for control planes that will be added to k3s's config.yaml. E.g to allow etcd monitoring."
}

variable "agent_nodes_custom_config" {
  type        = any
  default     = {}
  description = "Additional configuration for agent nodes and autoscaler nodes that will be added to k3s's config.yaml. E.g to allow kube-proxy monitoring."
}

variable "k3s_registries" {
  description = "K3S registries.yml contents. It is used to access private docker registries."
  default     = " "
  type        = string
}

variable "k3s_kubelet_config" {
  description = "K3S kubelet-config.yaml contents. Used to configure the kubelet."
  default     = ""
  type        = string
}

variable "k3s_audit_policy_config" {
  description = "K3S audit-policy.yaml contents. Used to configure Kubernetes audit logging."
  default     = ""
  type        = string
}

variable "k3s_audit_log_path" {
  description = "Path where audit logs will be stored on control plane nodes"
  default     = "/var/log/k3s-audit/audit.log"
  type        = string
}

variable "k3s_audit_log_maxage" {
  description = "Maximum number of days to retain audit log files"
  default     = 30
  type        = number
}

variable "k3s_audit_log_maxbackup" {
  description = "Maximum number of audit log files to retain"
  default     = 10
  type        = number
}

variable "k3s_audit_log_maxsize" {
  description = "Maximum size in megabytes of the audit log file before rotation"
  default     = 100
  type        = number
}

variable "additional_tls_sans" {
  description = "Additional TLS SANs to allow connection to control-plane through it."
  default     = []
  type        = list(string)
}

variable "k3s_exec_server_args" {
  type        = string
  default     = ""
  description = "The control plane is started with `k3s server {k3s_exec_server_args}`. Use this to add kube-apiserver-arg for example."
}

variable "k3s_exec_agent_args" {
  type        = string
  default     = ""
  description = "Agents nodes are started with `k3s agent {k3s_exec_agent_args}`. Use this to add kubelet-arg for example."
}

variable "k3s_prefer_bundled_bin" {
  type        = bool
  default     = false
  description = "Whether to use the bundled k3s mount binary instead of the one from the distro's util-linux package."
}

variable "k3s_global_kubelet_args" {
  type        = list(string)
  default     = []
  description = "Global kubelet args for all nodes."
}

variable "k3s_control_plane_kubelet_args" {
  type        = list(string)
  default     = []
  description = "Kubelet args for control plane nodes."
}

variable "k3s_agent_kubelet_args" {
  type        = list(string)
  default     = []
  description = "Kubelet args for agent nodes."
}

variable "k3s_autoscaler_kubelet_args" {
  type        = list(string)
  default     = []
  description = "Kubelet args for autoscaler nodes."
}

variable "ingress_target_namespace" {
  type        = string
  default     = ""
  description = "The namespace to deploy the ingress controller to. Defaults to ingress name."
}

variable "enable_local_storage" {
  type        = bool
  default     = false
  description = "Whether to enable or disable k3s local-storage. Warning: when enabled, there will be two default storage classes: \"local-path\" and \"hcloud-volumes\"!"
}

variable "disable_selinux" {
  type        = bool
  default     = false
  description = "Disable SELinux on all nodes."
}

variable "enable_delete_protection" {
  type = object({
    floating_ip   = optional(bool, false)
    load_balancer = optional(bool, false)
    volume        = optional(bool, false)
  })
  default = {
    floating_ip   = false
    load_balancer = false
    volume        = false
  }
  description = "Enable or disable delete protection for resources in Hetzner Cloud."
}

variable "keep_disk_agents" {
  type        = bool
  default     = false
  description = "Whether to keep OS disks of nodes the same size when upgrading an agent node"
}

variable "keep_disk_cp" {
  type        = bool
  default     = false
  description = "Whether to keep OS disks of nodes the same size when upgrading a control-plane node"
}


variable "sys_upgrade_controller_version" {
  type        = string
  default     = "v0.18.0"
  description = "Version of the System Upgrade Controller for automated upgrades of k3s. v0.15.0+ supports the 'window' parameter for scheduling upgrades. See https://github.com/rancher/system-upgrade-controller/releases for available versions."
}

variable "hetzner_ccm_values" {
  type        = string
  default     = ""
  description = "Additional helm values file to pass to Hetzner Controller Manager as 'valuesContent' at the HelmChart."
}

variable "hetzner_ccm_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or hetzner_ccm_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.hetzner_ccm_merge_values == "" || can(yamldecode(var.hetzner_ccm_merge_values))
    error_message = "hetzner_ccm_merge_values must be valid YAML format or empty string."
  }
}

variable "control_plane_endpoint" {
  type        = string
  description = "Optional external control plane endpoint URL (e.g. https://myapi.domain.com:6443). Used as the k3s 'server' value for agents and secondary control planes."
  default     = null
  validation {
    condition     = var.control_plane_endpoint == null || can(regex("^https?://(?:(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)*[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?|(?:[0-9]{1,3}\\.){3}[0-9]{1,3}|\\[[0-9a-fA-F:]+\\])(?::[0-9]{1,5})?(?:/.*)?$", var.control_plane_endpoint))
    error_message = "The control_plane_endpoint must be null or a valid URL (e.g., https://my-api.example.com:6443)."
  }
}

### ArgoCD Configuration
variable "enable_argocd" {
  description = "ArgoCD deployment toggle"
  type        = bool
  default     = false
}

variable "argocd_version" {
  type        = string
  default     = "*"
  description = "Version of the ArgoCD Helm chart. See https://github.com/argoproj/argo-helm/releases for the available versions."
}

variable "argocd_ingress_hostname" {
  type        = string
  default     = ""
  description = "Hostname to expose the ArgoCD UI via the Traefik ingress (e.g. argocd.example.com). Leave empty to skip ingress creation."
}

variable "argocd_github_repo_url" {
  type        = string
  default     = ""
  description = "HTTPS URL of the GitHub repository ArgoCD should monitor for app manifests (e.g. https://github.com/org/repo)."
}

variable "argocd_github_username" {
  type        = string
  default     = ""
  description = "GitHub username used for repository authentication and as the GHCR image pull secret identity."
}

variable "argocd_github_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "GitHub Personal Access Token used by ArgoCD to access the private repository and pull images from GHCR."
}

variable "argocd_apps_path" {
  type        = string
  default     = "kubernetes/apps"
  description = "Path inside the repository that contains the app-of-apps manifests ArgoCD should track."
}

variable "argocd_values" {
  type        = string
  default     = ""
  description = "Full override for the ArgoCD Helm chart values. When set, the default values are replaced entirely."
}

variable "argocd_merge_values" {
  type        = string
  default     = ""
  description = "Additional ArgoCD Helm chart values to deep-merge on top of the defaults."
}

### DNS Configuration
variable "dns_zone" {
  type        = string
  default     = "s8-hetzner.online"
  description = "The DNS zone managed in Hetzner DNS (e.g. s8-hetzner.online). A wildcard A record is created pointing to the Traefik LB IP."
}

### TLS / Let's Encrypt
variable "acme_email" {
  type        = string
  default     = ""
  description = "Email address registered with Let's Encrypt for certificate expiry notifications. Required when enable_cert_manager = true."
  validation {
    condition     = (var.acme_email == "" && var.enable_cert_manager == false) || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.acme_email))
    error_message = "The acme_email must be a valid email address or an empty string if cert manager is disabled."
  }
}

variable "issuer_environment" {
  type        = string
  default     = "prod"
  description = "The ACME issuer environment for cert manager. Supported values are 'prod' and 'staging'. The staging environment should be used for testing to avoid hitting Let's Encrypt rate limits."
  validation {
    condition     = contains(["prod", "staging"], var.issuer_environment)
    error_message = "The issuer_environment must be either 'prod' or 'staging'."
  }
}
