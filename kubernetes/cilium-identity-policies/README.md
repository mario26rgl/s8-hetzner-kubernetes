# cilium-identity-policies

This chart deploys identity-based `CiliumNetworkPolicy` objects used in the hybrid multi-cluster PoC.

## Policy model

- Frontend egress is allowed only when source identity, destination identity, and remote cluster identity match.
- Backend ingress is default-deny by omission and then explicitly allows only approved frontend identities.
- mTLS-style policy authentication is enforced with `authentication.mode: required`.
- L4 scope is restricted to backend TCP port `80`.

## Key values

- `frontend.namespace`: Namespace where tenant frontend pods run.
- `frontend.labels`: Labels selecting authorized frontend pods.
- `frontend.serviceAccount`: Required source service account identity.
- `backend.namespace`: Namespace for protected shared backend pods.
- `backend.labels`: Labels selecting protected backend pods.
- `clusterIdentity.allowedRemoteCluster`: Required cluster identity (`io.cilium.k8s.policy.cluster`).
- `authentication.mode`: Set to `required` to enforce policy auth.

## Example install

```bash
helm upgrade --install cilium-identity-policies \
  kubernetes/cilium-identity-policies \
  --namespace kube-system
```

## Hubble validation examples

```bash
hubble observe --verdict DROPPED --namespace shared-services
hubble observe --from-namespace tenant-one --to-namespace shared-services --protocol tcp
hubble observe --from-label k8s:io.cilium.k8s.policy.serviceaccount=frontend
```
