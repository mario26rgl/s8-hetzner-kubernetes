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
```

## Notes

- `name` should be DNS-safe and unique.
- `namespace` should be unique per tenant.
- `project` should be unique when `argocd.create_project` is true.
- Keep `vclusterOverrides` minimal to reduce drift.
