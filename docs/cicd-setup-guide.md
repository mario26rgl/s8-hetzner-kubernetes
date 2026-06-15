# Platform Setup Guide — CI/CD Walkthrough

End-to-end steps to bootstrap the Hetzner K3s platform from scratch using the GitHub Actions CI/CD pipeline.

---

## Prerequisites

Install the following tools locally before starting:

- `hcloud` CLI — [docs](https://github.com/hetznercloud/cli)
- `packer` ≥ 1.9 — [docs](https://developer.hashicorp.com/packer/install)
- `terraform` ≥ 1.10.1 — [docs](https://developer.hashicorp.com/terraform/install)
- `aws` CLI — [docs](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- `ssh-keygen`

---

## Step 1 — Create a Hetzner Project and API Token

1. Log in to [console.hetzner.cloud](https://console.hetzner.cloud).
2. Create a new project (e.g. `s8-hetzner`).
3. Inside the project, go to **Security → API Tokens → Generate API Token**.
   - Name: `terraform`
   - Permissions: **Read & Write**
4. Copy the token — it is shown only once. This is your `HCLOUD_TOKEN`.

---

## Step 2 — Create an AWS IAM User for S3 State

Terraform state and plan artifacts are stored in S3 bucket `s8-hetzner-k8s-tfstate` (region `eu-central-1`).

1. In the [AWS IAM console](https://console.aws.amazon.com/iam), create a user (e.g. `terraform-s3`).
2. Attach a policy granting at minimum `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` on `arn:aws:s3:::s8-hetzner-k8s-tfstate` and `arn:aws:s3:::s8-hetzner-k8s-tfstate/*`.
3. Create an **Access Key** for the user. Save the `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
4. Create the bucket if it does not exist yet:

```sh
aws s3api create-bucket \
  --bucket s8-hetzner-k8s-tfstate \
  --region eu-central-1 \
  --create-bucket-configuration LocationConstraint=eu-central-1
```

Enable versioning (recommended for state safety):

```bash
aws s3api put-bucket-versioning \
  --bucket s8-hetzner-k8s-tfstate \
  --versioning-configuration Status=Enabled
```

---

## Step 3 — Create a GitHub PAT for ArgoCD

ArgoCD needs read access to this repository to sync Kubernetes manifests.

1. Go to **GitHub → Settings → Developer Settings → Personal Access Tokens → Fine-grained tokens**.
2. Create a token scoped to this repository with **Contents: Read-only**.
3. Copy the token. This is your `ARGOCD_PAT`.

---

## Step 4 — Generate an SSH Key Pair

The key pair is used for node provisioning. Control-plane and agent nodes have public IPs disabled, so SSH access goes through the NAT router.

```bash
ssh-keygen -t ed25519 -C "k3s-hetzner" -f ~/.ssh/k3s_hetzner
```

- `~/.ssh/k3s_hetzner.pub` → value for `ssh_public_key` in `PROD.tfvars`
- `~/.ssh/k3s_hetzner` → value for `SSH_PRIVATE_KEY` GitHub secret

Add the public key to Hetzner: **Security → SSH Keys → Add SSH Key**.

---

## Step 5 — Build and Push the MicroOS Packer Image

The Terraform data source `hcloud_image.microos_x86_snapshot` looks for a snapshot labelled `microos-snapshot=yes` in the Hetzner project. Build it once before the first `terraform apply`.

```bash
export HCLOUD_TOKEN=<your-hcloud-token>
cd packer
./create.sh
```

The script runs `packer init` and `packer build`, which:
1. Creates a temporary `cx23` rescue server in `nbg1`.
2. Downloads the OpenSUSE MicroOS qcow2 image and writes it to disk.
3. Installs required packages (wireguard-tools, open-iscsi, SELinux policy, k3s-selinux, etc.) via `transactional-update`.
4. Saves the result as a Hetzner snapshot named `OpenSUSE MicroOS x86 Hardened Image` with label `microos-snapshot=yes`.

> The build takes approximately 10–15 minutes. Run it again only when you need to refresh the base image.

---

## Step 6 — Configure `config/PROD.tfvars`

Edit `terraform/config/PROD.tfvars` with values for your environment. Required fields to update:

```hcl
# Your SSH public key (output of cat ~/.ssh/k3s_hetzner.pub)
ssh_public_key = "ssh-ed25519 AAAA... k3s-hetzner"

# Your domain (must be managed in Hetzner DNS)
argocd_ingress_hostname  = "argo.<your-domain>"
hubble_ingress_hostname  = "hubble.<your-domain>"

# ArgoCD repo & owner
argocd_github_repo_url  = "https://github.com/<org>/<repo>"
argocd_github_username  = "<github-username>"

# ACME email for cert-manager
acme_email = "<your-email>"

# Switch to "production" once staging certs are confirmed working
issuer_environment = "staging"

# Node pools — adjust server_type and count to your needs
control_plane_nodepools = [{ ... }]
agent_nodepools         = [{ ... }]
```

All other values (CNI, Cilium version, firewall rules, k3s version, etc.) are pre-configured and ready for use. Review and adjust as needed.

> `hcloud_token` is **not** set in the tfvars file. It is injected at runtime via the `TF_VAR_hcloud_token` environment variable in CI, populated from the `HCLOUD_TOKEN` GitHub secret.

---

## Step 7 — Add GitHub Actions Secrets

In the repository, go to **Settings → Secrets and variables → Actions** and add:

| Secret name            | Value                                      |
|------------------------|--------------------------------------------|
| `HCLOUD_TOKEN`         | Hetzner API token from Step 1              |
| `SSH_PRIVATE_KEY`      | Contents of `~/.ssh/k3s_hetzner` (private) |
| `AWS_ACCESS_KEY_ID`    | AWS access key from Step 2                 |
| `AWS_SECRET_ACCESS_KEY`| AWS secret key from Step 2                 |
| `ARGOCD_PAT`           | GitHub PAT from Step 3                     |

---

## Step 8 — Open a Pull Request to Trigger the Quality Gate

```bash
git checkout -b infra/initial-setup
# Make any change to terraform/ (e.g. update PROD.tfvars with your values)
git add terraform/config/PROD.tfvars
git commit -m "chore: configure PROD environment"
git push -u origin infra/initial-setup
```

Open a PR targeting `main`. The `tf-quality-gate` workflow runs automatically and:
1. **Lint** — runs `tflint` against the Terraform HCL.
2. **Security** — runs `trivy` in `config` mode, failing on CRITICAL/HIGH findings.
3. **Plan** — runs `terraform plan -var-file="./config/PROD.tfvars"`, uploads the binary plan to S3, and posts a truncated plan as a PR comment.

Wait for all three jobs to go green before proceeding.

---

## Step 9 — Review the Plan

In the PR, scroll to the comment posted by the `plan` job. Verify:

- Correct number of `hcloud_server` resources being created (control planes + agents + NAT router).
- Load balancers, network, subnets, and firewall are present.
- DNS records point to the expected LB IP.
- No unexpected destroys on existing resources.

If changes are needed, push additional commits — each push re-runs the quality gate and overwrites the plan artifact in S3.

---

## Step 10 — Merge to Main and Wait for Apply

Once the plan looks correct, merge the PR (use a standard merge commit, not squash/rebase, to preserve plan artifact traceability).

The `tf-apply` workflow triggers on push to `main` and:

1. Extracts the PR head SHA from the merge commit's second parent.
2. Downloads the exact binary plan from S3 that was reviewed in the PR.
3. Runs `terraform apply tfplan.binary` — applies the reviewed plan verbatim.
4. Deletes the plan artifact from S3 after apply.

If no plan artifact is found (squash merge / direct push), it falls back to a fresh `terraform apply -auto-approve`.

Monitor progress in **Actions → Terraform Apply**. A full bootstrap including K3s cluster init, Cilium, Traefik, cert-manager, and ArgoCD takes approximately 10–20 minutes.

---

## Step 11 — Access the Platform

Once apply completes, all services are reachable via their ingress hostnames. Retrieve the initial ArgoCD admin password:

```bash
# Get kubeconfig (written locally by Terraform or fetch from Terraform output)
export KUBECONFIG=./kubeconfig.yaml

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### Service URLs

| Service     | URL                                      | Credentials                                      |
|-------------|------------------------------------------|--------------------------------------------------|
| **ArgoCD**  | `https://argo.<your-domain>`             | user: `admin` / password: from secret above      |
| **Hubble**  | `https://hubble.<your-domain>`           | No auth (Cilium network observability UI)        |
| **OpenCost**| `https://opencost.<your-domain>`         | No auth by default                               |
| **Grafana** | `https://grafana.<your-domain>`          | user: `admin` / password: from kube-prometheus-stack secret |
| **App**     | `https://app.<your-domain>`              | Application-level credentials                   |

Retrieve Grafana admin password:

```bash
kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d
```

> Replace `<your-domain>` with the value of your domain as configured in `PROD.tfvars`.
> 
> All ingress hostnames use TLS certificates issued by cert-manager. If `issuer_environment = "staging"` is set, browsers will show an untrusted cert warning until you switch to `"production"` and re-apply.

---

## Troubleshooting

**Plan artifact not found during apply** — This happens on squash/rebase merges. The workflow falls back to a fresh apply automatically. To avoid this, always use standard merge commits.

**Packer snapshot not found** — Ensure Step 5 completed successfully and the snapshot exists in the correct Hetzner project (same project as `HCLOUD_TOKEN`). Check: `hcloud image list --type snapshot`.

**Cert-manager staging certificates** — Expected on first run. Update `issuer_environment = "production"` in `PROD.tfvars` and open a new PR once the cluster is healthy.

**Node provisioning timeout** — SSH provisioners connect via the NAT router. Ensure the NAT router server came up successfully: `hcloud server list`.

---

## Application Operations

Day-2 tasks performed after the cluster is running.

---

### Add a New Application via ArgoCD

All application state lives in `kubernetes/apps/`. ArgoCD watches that directory (configured by `argocd_apps_path = "kubernetes/apps"` in `PROD.tfvars`) and syncs every manifest it finds there automatically.

#### Using the `service` chart (stateless microservice)

Create `kubernetes/apps/<your-service>.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-service
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/<org>/<repo>.git'
    targetRevision: main
    path: kubernetes/service
    helm:
      valuesObject:
        name: my-service
        namespace: my-service
        image: ghcr.io/<org>/my-service@sha256:<digest>
        replicas: 2
        port: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
        autoscaling:
          hpa:
            enabled: true
            minReplicas: 1
            maxReplicas: 3
            targetCPUUtilizationPercentage: 80
          vpa:
            enabled: true
            updateMode: Auto
            controlledValues: RequestsAndLimits
            minAllowed:
              cpu: 50m
              memory: 64Mi
            maxAllowed:
              cpu: 500m
              memory: 512Mi
        env:
          SOME_ENV_VAR: some-value
        # Optional: expose via Traefik ingress
        ingress:
          enabled: true
          hostname: "my-service.<your-domain>"
          environment: production   # or staging
        # Optional: Cilium network policy
        networkPolicy:
          enabled: false
  destination:
    server: https://kubernetes.default.svc
    namespace: my-service
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - RespectIgnoreDifferences=true
    automated:
      prune: true
      selfHeal: true
```

Key `service` chart values:

| Field | Purpose |
|---|---|
| `name` | Deployment/Service name and pod label `app:` |
| `image` | Full image reference; use digest pins (`@sha256:`) for immutability |
| `port` | Container and Service port |
| `env` | Environment variables injected into the container |
| `ingress.enabled` | Creates a Traefik `IngressRoute` if `true` |
| `networkPolicy.enabled` | Creates a `CiliumNetworkPolicy` if `true` |
| `autoscaling.hpa` / `vpa` | HPA and VPA configuration |

#### Using the `database` chart (stateful service)

Create `kubernetes/apps/<your-db>.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-db
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/<org>/<repo>.git'
    targetRevision: main
    path: kubernetes/database
    helm:
      valuesObject:
        name: my-db
        namespace: my-db
        image: postgres:16.3
        replicas: 1
        servicePort: 5432
        containerPort: 5432
        env:
          PGDATA: /var/lib/postgresql/data/pgdata
        secret:
          POSTGRES_USER: myuser
          POSTGRES_PASSWORD: changeme
          POSTGRES_DB: mydb
        persistence:
          enabled: true
          size: 10Gi
          mountPath: /var/lib/postgresql/data
        bootstrap:
          enabled: false   # set true to run users.sql on first boot
  destination:
    server: https://kubernetes.default.svc
    namespace: my-db
  ignoreDifferences:
    - group: apps
      kind: StatefulSet
      jqPathExpressions:
        - .spec.volumeClaimTemplates[]
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - RespectIgnoreDifferences=true
    automated:
      prune: true
      selfHeal: true
```

#### Deploy

```bash
git checkout -b app/add-my-service
git add kubernetes/apps/my-service.yaml
git commit -m "feat: add my-service ArgoCD application"
git push -u origin app/add-my-service
```

Open a PR. ArgoCD picks up the manifest automatically once merged to `main` — no Terraform change needed.

---

### Upgrade the K3s Cluster Version

K3s upgrades are managed by `system-upgrade-controller` using `Plan` CRDs. Terraform renders those plans from `templates/plans.yaml.tpl` using `install_k3s_version` from `PROD.tfvars`.

1. Check the [K3s releases](https://github.com/k3s-io/k3s/releases) for the target version.
2. Update `terraform/config/PROD.tfvars`:

```hcl
install_k3s_version = "v1.35.5+k3s1"   # was v1.35.4+k3s1
```

3. Open a PR. The quality gate runs `terraform plan` — verify the plan shows a change to the `plans.yaml` file upload inside `terraform_data.kustomization` and nothing destructive.
4. Merge. On apply, Terraform re-uploads `plans.yaml` to the control plane and applies it via `kubectl -n system-upgrade apply -f /var/post_install/plans.yaml`.
5. `system-upgrade-controller` then cordons and upgrades nodes one by one (agents first via the `k3s-agent` plan, then control-plane via `k3s-server`).

Monitor the upgrade:

```bash
kubectl -n system-upgrade get plans
kubectl -n system-upgrade get jobs
kubectl get nodes -w
```

> If `install_k3s_version` is set to `""`, the controller follows the channel specified by `initial_k3s_channel` instead (e.g. `stable`).

---

### Add a New Terraform Controller (Bootstrap Add-on)

Controllers bootstrapped by Terraform are uploaded to `/var/post_install/` on the first control plane and applied via `kubectl apply -k /var/post_install`. To add a new one, follow the same three-file pattern used by every existing add-on:

**1. Create the template** — `terraform/templates/<controller>.yaml.tpl`

This is a standard Kubernetes manifest, optionally using Terraform template interpolation (`${variable}`). Use a K3s `HelmChart` CRD for Helm-based controllers:

```yaml
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: my-controller
  namespace: kube-system
spec:
  chart: my-controller
  repo: https://my-controller.github.io/helm-charts
  version: "${version}"
  targetNamespace: my-controller
  createNamespace: true
  valuesContent: |-
    ${values}
```

**2. Upload the rendered template in `terraform/init.tf`**

Inside the `terraform_data.kustomization` resource, add a `provisioner "file"` block alongside the existing ones:

```hcl
provisioner "file" {
  content = templatefile(
    "${path.module}/templates/my-controller.yaml.tpl",
    {
      version = var.my_controller_version
      values  = indent(4, local.my_controller_values)
    }
  )
  destination = "/var/post_install/my-controller.yaml"
}
```

**3. Add the variable and local values** — `terraform/variables.tf` and `terraform/locals.tf`

In `variables.tf`:

```hcl
variable "my_controller_version" {
  type        = string
  default     = "1.0.0"
  description = "Version of my-controller Helm chart."
}
```

In `locals.tf`, add the rendered Helm values (follow the `traefik_values` / `cilium_values` pattern):

```hcl
locals {
  my_controller_values = yamlencode({
    replicaCount = 1
    # ... chart-specific values
  })
}
```

**4. Set the version in `PROD.tfvars`** (optional, if you want to pin it per environment):

```hcl
my_controller_version = "1.2.3"
```

**5. Open a PR** — the quality gate plans the change. On merge, Terraform SSHes into the control plane, uploads the rendered manifest, and re-runs `kubectl apply -k /var/post_install`.

> The `kustomization.yaml` is generated by Terraform (`local.kustomization_yaml`) and includes every file in `/var/post_install/`. Adding a new file there is enough — no manual kustomization.yaml editing required.
