# Tenant Onboarding

This folder contains the source of truth for tenant bootstrap.

## Flow

1. Add a new object to `tenants` in `tenants.yaml`.
2. Commit and open a PR.
3. After merge, Argo CD ApplicationSet in `kubernetes/apps/vcluster-tenants.yaml` generates one tenant bootstrap application.
4. The tenant bootstrap application deploys:
   - vcluster Argo CD application
   - ESO bridge resources for vcluster kubeconfig import
   - Argo CD cluster secret for destination registration
   - tenant AppProject (when `argocd.create_project` is enabled)
5. The tenant access application deploys:
  - Argo CD local account mappings for tenant users
  - RBAC bindings from local user to tenant project role
  - ExternalSecret resources that merge password hashes into `argocd-secret`
  - ExternalSecret repository credentials from AWS Secrets Manager

## Example

```yaml
tenants:
  - name: tenant-acme
    namespace: tenant-acme
    project: tenant-acme
    chartVersion: "0.33.1"
    sourceRepos:
      - https://github.com/mario26rgl/s8-hetzner-kubernetes.git
    vclusterOverrides: |
      telemetry:
        enabled: false
    argocdUser:
      username: tenant-acme-admin
      roleName: tenant-admin
      passwordHashSecretRef:
        key: /argocd/tenants/tenant-acme/user
        property: passwordHash
      passwordMtimeSecretRef:
        key: /argocd/tenants/tenant-acme/user
        property: passwordMtime
    repoCredentials:
      enabled: true
      authType: basic
      name: tenant-acme-repo
      secretRef:
        key: /argocd/tenants/tenant-acme/repo
        urlProperty: url
        usernameProperty: username
        passwordProperty: password
```

## Notes

- `name` should be DNS-safe and unique.
- `namespace` should be unique per tenant.
- `project` should be unique when `argocd.create_project` is true.
- Keep `vclusterOverrides` minimal to reduce drift.
- `argocdUser.passwordHashSecretRef` should point to a bcrypt hash, not plain text.
- `repoCredentials.secretRef` should point to an AWS secret with URL and auth fields.
- Expected default store reference is `ClusterSecretStore/aws-secretsmanager` (override in the tenant-access app values if needed).
