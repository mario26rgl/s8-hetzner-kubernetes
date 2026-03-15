---
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
---
# Repository credentials secret – grants ArgoCD read access to the private GitHub repository.
# ArgoCD discovers this secret via the argocd.argoproj.io/secret-type label.
apiVersion: v1
kind: Secret
metadata:
  name: argocd-repo-github
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  url: ${github_repo_url}
  username: ${github_username}
  password: ${github_token}
---
# GHCR image pull secret – used to pull private container images from ghcr.io.
# Referenced via imagePullSecrets in pod specs
# apiVersion: v1
# kind: Secret
# metadata:
#  name: ghcr-pull-secret
#  namespace: argocd
# type: kubernetes.io/dockerconfigjson
# stringData:
#   .dockerconfigjson: '{"auths":{"ghcr.io":{"username":"${github_username}","password":"${github_token}","auth":"${ghcr_auth}"}}}'
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: argocd
  namespace: kube-system
spec:
  chart: argo-cd
  version: "${version}"
  repo: https://argoproj.github.io/argo-helm
  targetNamespace: argocd
  createNamespace: false
  valuesContent: |-
    ${values}
