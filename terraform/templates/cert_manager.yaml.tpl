---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: cert-manager
  namespace: kube-system
spec:
  chart: cert-manager
  version: "${version}"
  repo: https://charts.jetstack.io
  targetNamespace: cert-manager
  bootstrap: ${bootstrap}
  valuesContent: |-
    ${values}
