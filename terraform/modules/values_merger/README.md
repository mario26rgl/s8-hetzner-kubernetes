# Module `modules/values_merger`

Purpose: merge Helm YAML values from a chart's default, an override, and optional patch values using the `isometry/deepmerge` provider so Terraform can render final chart values during bootstrap.

## Inputs

- `default_values` (string) — YAML string representing default chart values.
- `override_values` (string) — YAML string used to override defaults.
- `merge_values` (string) — YAML string used to deep-merge into the base values (patch semantics).

## Outputs

- `values` (string) — Final YAML string produced by `deepmerge::mergo` or the chosen base when no merge is requested.

## Behavior

- If `override_values` is provided it becomes the `base_values` for merging; otherwise `default_values` is used.
- If `merge_values` is provided, the module decodes YAML, merges with `provider::deepmerge::mergo` and re-encodes to YAML via `yamlencode()` producing the `values` output.
- Designed to be called from the root module for various charts (Cilium, Traefik, cert-manager) so Terraform can compute effective Helm values without requiring external templating steps.
