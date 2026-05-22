# s8-hetzner-kubernetes — Hetzner Infrastructure (Terraform) Focus

This repository contains the Infrastructure-as-Code (IaC) and bootstrap artifacts used to provision and operate a self-managed K3s Kubernetes platform running on Hetzner Cloud. The content here is centered on the Hetzner deployment path: network, nodes, NAT, load balancers, DNS integration, node images, and the Terraform-driven bootstrap of cluster add-ons.

This README is intentionally scoped to the Hetzner / Terraform implementation. It omits tenant/vcluster application logic and auxiliary AWS PoC material contained elsewhere in the repository.

**What this repo provides (IaC only)**
- Hetzner network topology and subnets (control-plane, agents, NAT)
- Node lifecycle module for control-plane and agent servers (cloud-init, OS image, post-config)
- NAT router for private-only nodes and outbound internet access
- Hetzner Load Balancers for control-plane and ingress (Traefik) endpoints
- Firewalling, SSH key provisioning and DNS records (Hetzner DNS)
- K3s bootstrap orchestration and remote kustomization-based add-on install (Cilium, Traefik, cert-manager, kured, system-upgrade-controller)
- Packer-based node image build artifacts for reproducible nodes
- GitHub Actions CI for Terraform quality gate, plan artifact storage, and controlled apply

**Scope note:** This README concentrates on Terraform-driven infrastructure and CI/CD that manages it. Application-level services and multi-tenant vcluster logic are intentionally out of scope.

**Quick start (operational)**

1. Configure `config/PROD.tfvars` with your Hetzner credentials and environment values.
2. Initialize Terraform:

```bash
cd terraform
terraform init
terraform plan -var-file=../config/PROD.tfvars
terraform apply -var-file=../config/PROD.tfvars
```

Replace `PROD.tfvars` with your environment override.

**Repository layout (IaC-focused)**

The structure below highlights the most relevant IaC areas and common edit targets.

- `terraform/` — Root Terraform module and orchestration for Hetzner K3s cluster. Primary place to author/inspect infrastructure.
  - `modules/host/` — Node lifecycle module used to create and configure `hcloud_server` instances. Contains cloud-init templates and post-provision hooks.
  - `modules/values_merger/` — Helpers that deep-merge Helm/YAML values so Terraform can render effective chart values during bootstrap.
  - `templates/` — Go-templates and Terraform template files used to render manifests and cloud-init payloads.
- `kubernetes/` — Kubernetes bootstrap manifests, Helm charts and kustomizations that Terraform applies during cluster bootstrap (Cilium, Traefik, cert-manager, kured, system-upgrade-controller).
- `cilium-clustermesh/` — Values & helper scripts for Cilium ClusterMesh (kept for reference; ClusterMesh is not the primary Hetzner-only flow).
- `packer/` — Packer definitions and a `create.sh` wrapper to build reproducible node images (OpenSUSE MicroOS example).
- `scripts/` — Utility scripts for one-off tasks and example manifests (e.g., `secret-delete.sh`, `pod-on-external.yaml`).
- `config/` — Environment override files. `PROD.tfvars` is the recommended starting file for production-like runs.
- `.github/workflows/` — Terraform CI: PR quality gate and push-to-main apply workflows (`tf-quality-gate.yaml`, `tf-apply.yaml`).

Visual tree (quick reference)

terraform/
├─ modules/
│  ├─ host/                # node provisioning, cloud-init templates
│  └─ values_merger/       # YAML merge helpers for Helm chart values
├─ templates/              # manifest/cloud-init templates used by modules
├─ main.tf                 # root module wiring (networks, LBs, nodes)
└─ outputs.tf              # kubeconfig, tokens, LB IPs

kubernetes/
├─ backend/                # Chart + manifests for demo backend
├─ frontend/               # Chart + manifests for demo frontend
└─ argocd-*.yaml           # argocd bootstrap manifests used during k8s bootstrap

packer/
└─ hardened-image.pkr.hcl  # packer image build definition

.github/workflows/
├─ tf-quality-gate.yaml    # PR lint, security, plan (uploads plan artifact)
└─ tf-apply.yaml           # push-to-main apply (consumes plan artifact)

Architecture (high-level)

Terraform root module composes Hetzner resources and child modules to produce:

- Network (private Hetzner network + per-role subnets)
- NAT router and routing rules for private-only nodes
- Control-plane servers + control-plane load balancer
- Agent pools (agent server groups) and optional autoscaler integration
- Ingress Load Balancer for Traefik
- SSH keys, firewalls and DNS records
- Outputs: kubeconfig, k3s_token, cluster IPs and LB addresses

Key implemented resources (Hetzner-centric)

- `hcloud_network`, `hcloud_network_subnet` — private network + subnets for control-plane, agents, nat-router
- `hcloud_server` (via `modules/host`) — control-plane, agent and NAT router servers
- `hcloud_firewall` — firewall rules for cluster and management access
- `hcloud_load_balancer`, `hcloud_load_balancer_service`, `hcloud_load_balancer_target` — control-plane & ingress LBs
- `hcloud_primary_ip` — public IPs for NAT router or LBs where needed
- `hcloud_zone_rrset` — DNS A records (wildcard and apex) in Hetzner DNS
- `cloudinit_config` — cloud-init user data rendered per node type
- `local_sensitive_file` / `ssh_sensitive_resource` — kubeconfig rendering and secure storage during bootstrap

Terraform (tfdocs-style) snapshot

### Requirements

| Name | Version |
|---|---|
| terraform | `>= 1.10.1` |

### Backend

| Type | Key Settings |
|---|---|
| `s3` (optional plan artifact backend used by CI) | bucket `s8-hetzner-k8s-tfstate`, region `eu-central-1`, key prefix `backend/terraform.tfstate` |

### Providers (primary for Hetzner IaC)

| Name | Source | Version Constraint |
|---|---|---|
| hcloud | hetznercloud/hcloud | `>= 1.59.0` |
| cloudinit | hashicorp/cloudinit | `>= 2.3.7` |
| deepmerge | isometry/deepmerge | `~> 1.0` |
| github | integrations/github | `>= 6.4.0` |
| local | hashicorp/local | `>= 2.5.2` |
| random | hashicorp/random | `>= 3.8.1` |
| ssh | loafoe/ssh | `2.7.0` |

### Modules

| Name | Source | Purpose |
|---|---|---|
| agents | `./modules/host` | Agent node lifecycle and post-config |
| control_planes | `./modules/host` | Control-plane node lifecycle and post-config |
| values_merger_* | `./modules/values_merger` | Merge Helm/chart values for bootstrap flows |

### Data sources

- `hcloud_image.microos_x86_snapshot`
- `hcloud_load_balancer.traefik`
- `hcloud_ssh_keys.keys_by_selector`
- `hcloud_zone.main`
- `github_release.*` (used to resolve chart versions for some bootstrap components)
- `cloudinit_config.*` (autoscaler, nat-router)

### Important root-module resources (representative)

- `hcloud_network.k3s`
- `hcloud_network_subnet.control_plane`
- `hcloud_network_subnet.agent`
- `hcloud_server.nat_router`
- `hcloud_primary_ip.nat_router_primary_ipv4`
- `hcloud_load_balancer.control_plane`
- `hcloud_load_balancer.cluster`
- `hcloud_firewall.k3s`
- `hcloud_zone_rrset.apex` / `hcloud_zone_rrset.wildcard`
- `local_sensitive_file.kubeconfig`
- `random_password.k3s_token`

---

**tfdocs-style resource descriptions (what each resource does)**

- `hcloud_network.k3s`
  - What it does: Creates a private Hetzner network that isolates cluster traffic from the public internet. This network provides L2 connectivity between `hcloud_server` instances and is the backbone for private subnets.
  - Important arguments: `ip_range` (CIDR used for private addressing), `labels`.
  - Key outputs/use: Network `id` used by `hcloud_server` attachments and `hcloud_network_subnet` creation.

- `hcloud_network_subnet.*` (`control_plane`, `agent`, `nat_router`)
  - What it does: Declares subnet partitions inside the `hcloud_network` for role-based segregation (control-plane vs agent vs NAT router). Subnets constrain IP allocation ranges and help express routing rules.
  - Important arguments: `network_id`, `type` (e.g., `cloud`), `ip_range`.
  - Key outputs/use: Subnet IDs used when attaching servers, and to generate route table entries for NAT/router logic.

- `hcloud_server` (via `modules/host`)
  - What it does: Provisions Hetzner Cloud VMs for control-plane nodes, agent nodes, and the NAT router. The `modules/host` module wraps `hcloud_server` with cloud-init injection, SSH key setup, and node-specific post-provisioning hooks (e.g., registering kubelet, running OS hardening or system-upgrade scripts).
  - Important arguments (module-level): `image`, `server_type`, `ssh_keys`, `user_data` (cloud-init), `network_subnet_id`, `labels`, `public_net`.
  - Key outputs/use: Each server exposes a private IP, optional public IP, and is referenced by other resources like LBs and firewalls.

- `hcloud_primary_ip` (NAT/router public IP)
  - What it does: Reserves a static public IP address that can be attached to the NAT router or a load balancer. Useful when you need a stable public endpoint for API or ingress.
  - Important arguments: `type` (ipv4/ipv6), `labels`.
  - Key outputs/use: Public IP value used in DNS records and external routing configuration.

- `hcloud_load_balancer`, `hcloud_load_balancer_service`, `hcloud_load_balancer_target`
  - What it does: Creates Hetzner Load Balancers used to front the K3s API (control-plane LB) and the cluster ingress (Traefik). `hcloud_load_balancer_service` configures port/protocol/health checks; `hcloud_load_balancer_target` attaches backend servers by private IP.
  - Important arguments: `algorithm` (round-robin), `location`, `services` block (ports, protocol), `targets` (server or IP targets).
  - Key outputs/use: LB IPs used as `k3s_endpoint`, and ingress host address for Traefik.

- `hcloud_firewall.k3s`
  - What it does: Defines firewall rules applied to servers in the cluster to restrict access to the API, kubelet, SSH, and other management ports. Typically allows SSH from admin CIDRs, API access from LB/private network, and kubelet ports between nodes.
  - Important arguments: `inbound_rules`, `outbound_rules`, `apply_to` (server labels or IDs).
  - Key outputs/use: Applied as a security boundary for cluster control-plane and nodes.

- `hcloud_zone_rrset.apex` / `hcloud_zone_rrset.wildcard`
  - What it does: Manages Hetzner DNS records (apex and wildcard) used by ingress and bootstrap components. Ensures the LB public IPs are resolvable for ACME and operator workflows.
  - Important arguments: `zone`, `type` (A/AAAA), `records` (IP addresses), `ttl`.
  - Key outputs/use: DNS names and records used by `traefik` ingress and cert-manager.

- `cloudinit_config.*`
  - What it does: Renders `cloud-init` user-data for node bootstrapping. Typical contents: package installs, systemd unit creation, k3s install command, kubelet configuration, registry mirrors, and post-install hooks.
  - Important arguments: `rendered` user data, file attachments, and template variables for kubelet/k3s settings.
  - Key outputs/use: Supplied to `hcloud_server` as `user_data` to ensure immutable, reproducible node provisioning.

- `local_sensitive_file.kubeconfig` / `ssh_sensitive_resource.kubeconfig`
  - What it does: Writes rendered sensitive artifacts (like a kubeconfig) to local files during the Terraform run, with careful handling to avoid committing secrets. These are used to validate bootstrap steps during provisioning.
  - Important arguments: `content` (sensitive), `file_permission`.
  - Key outputs/use: Temporary file paths consumed by local-exec or provisioning scripts.

- `random_password.k3s_token`
  - What it does: Generates the cluster `k3s_token` (sensitive) used to join agents to the control-plane. Stored as Terraform-sensitive output and used only in provisioning steps or exported to secret backends when required.
  - Important arguments: `length`, `special` flags.

---

Inputs (high-level)

- `hcloud_token` — Hetzner API token (sensitive)
- `ssh_public_key`, `ssh_private_key`, `ssh_hcloud_key_label`
- `network_ipv4_cidr`, `cluster_ipv4_cidr`, `service_ipv4_cidr`
- `control_plane_nodepools`, `agent_nodepools`, `autoscaler_*`
- `enable_wireguard` (Cilium/transport options)
- `enable_cert_manager`, `ingress_controller`, `traefik_*`
- `kubeconfig_server_address`, `lb_hostname`

Outputs (high-level)

- `cluster_name` — cluster identifier
- `network_id` — Hetzner network ID
- `control_planes_private_ipv4` — private IPs of control-plane nodes
- `agents_private_ipv4` — private IPs of agent nodes
- `ingress_public_ipv4` — ingress load balancer IP
- `k3s_endpoint` — API endpoint to register agents
- `k3s_token` — cluster join token (sensitive)
- `kubeconfig` / `kubeconfig_data` — rendered kubeconfig for cluster access

CI / GitHub Actions (Terraform quality gate and apply)

This repository includes CI workflows that are integrated with the Terraform authoring lifecycle:

- `.github/workflows/tf-quality-gate.yaml` — PR-triggered quality gate that runs:
  - `tflint` configuration linting and policy checks
  - `trivy` configuration security scanning against the `terraform/` directory
  - `terraform plan` using `config/PROD.tfvars` to produce a binary plan artifact
  - Upload of the plan artifact to an S3 bucket and posting a truncated plan as a PR comment

- `.github/workflows/tf-apply.yaml` — push-to-main apply workflow that:
  - Detects whether a plan artifact exists for the merged PR head (downloaded from S3)
  - Applies the exact binary plan if available (guarantees plan→apply consistency)
  - Falls back to a fresh `terraform apply` when no plan artifact is available (e.g., squash/rebase/direct push)
  - Uses the `webfactory/ssh-agent` action to provision SSH credentials for bootstrap actions
  - Requires the following GitHub `secrets`: `HCLOUD_TOKEN`, `SSH_PRIVATE_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and optionally `ARGOCD_PAT` (used by some bootstrap flows)

CI implementation notes

- Plan artifact storage: the workflows store the plan binary under an S3 bucket `s8-hetzner-k8s-tfstate` (see `TF_PLAN_BUCKET` env) and use the PR branch SHA to name artifacts. The apply workflow detects merge commits with two parents and attempts to retrieve the plan produced during PR validation.
- Security scanning: `trivy` runs in `config` mode to find risky Terraform configuration issues before plans are produced.
- Linting: `tflint` is initialized and executed as part of the PR quality gate.

CI workflow step-by-step (what each job/step does)

- `tf-quality-gate.yaml` (runs on PRs that touch `terraform/**`)
  - Job: `lint` — sets up `tflint` and runs `tflint --init` then `tflint -f compact` to validate Terraform HCL and provider rules. This prevents common misconfigurations before planning.
  - Job: `security` — runs `aquasecurity/trivy-action` in `config` mode against the `terraform/` directory. It scans Terraform files for insecure patterns and reports `CRITICAL`/`HIGH` issues.
  - Job: `plan` (depends on `lint` and `security`) — prepares and runs `terraform init` and `terraform plan -var-file="../config/PROD.tfvars" -out=tfplan.binary`. This produces a binary plan artifact and `plan.txt` human-readable output. The job then:
    - Uploads `tfplan.binary` to an S3 bucket (configured by `TF_PLAN_BUCKET`/`TF_PLAN_PREFIX`) keyed by the PR head SHA.
    - Posts a truncated plan preview as a comment on the PR so reviewers can inspect the exact changes.

- `tf-apply.yaml` (runs on push to `main` when `terraform/**` changed)
  - Checks out the repository with full history (fetch-depth: 0) so the workflow can inspect merge commit parents.
  - Uses `webfactory/ssh-agent` to load `SSH_PRIVATE_KEY` into an SSH agent for later remote provisioning steps during apply.
  - Runs `terraform init` in `terraform/`.
  - Resolves plan artifact: inspects the current commit parents — for regular merge commits it extracts the PR head SHA (second parent) and attempts to download `tfplan-<PR_HEAD_SHA>.binary` from the S3 plan bucket.
    - If the plan artifact exists: the workflow applies that exact binary plan with `terraform apply <binary>` (guarantees the plan reviewed in PR is the one applied).
    - If the artifact is missing (squash/rebase/direct push or missing upload): it falls back to running `terraform apply -auto-approve -var-file="../config/PROD.tfvars"` to perform a fresh apply.
  - Cleanup: when a plan artifact was used, the workflow deletes the S3 object to avoid leaving stale plans.

Secrets and environment used by CI

- `HCLOUD_TOKEN` (Terraform provider credential)
- `SSH_PRIVATE_KEY` (used by `webfactory/ssh-agent` to allow remote provisioners to connect)
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (used to upload/download plan artifacts to S3)
- `ARGOCD_PAT` (optional token used by some bootstrap flows during `terraform` operations)

These workflows emphasize a safe plan → apply cycle by storing plan binaries produced on PR and applying them verbatim on merge whenever possible. The quality gate enforces linting and static security scanning before any plan is produced.

Operational runbook (concise)

Local plan & apply (manual run):

```bash
cd terraform
terraform init
terraform plan -var-file="../config/PROD.tfvars" -out=tfplan.binary
terraform apply tfplan.binary
```

CI-driven flow (recommended):

1. Open a PR with Terraform changes under `terraform/**`.
2. Wait for `tf-quality-gate` to complete (lint, security, plan). The plan is published to S3 and posted in the PR.
3. Merge to `main`. `tf-apply` will download and apply the exact plan binary produced for the PR (if present), otherwise it will run a fresh apply.

Where to look next

- `terraform/` — the canonical entrypoint for IaC changes and versioned Terraform modules.
- `modules/host/` — node lifecycle and cloud-init templates; primary place to harden node provisioning logic.
- `packer/` — image build routines for reproducible node images.
- `.github/workflows/` — CI workflows that enforce quality and manage plan artifacts.