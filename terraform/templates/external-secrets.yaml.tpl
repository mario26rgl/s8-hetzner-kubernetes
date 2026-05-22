---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: external-secrets
  namespace: kube-system
spec:
  chart: external-secrets
  version: "${version}"
  repo: https://charts.external-secrets.io
  targetNamespace: external-secrets
  createNamespace: true
  valuesContent: |-
    ${values}
