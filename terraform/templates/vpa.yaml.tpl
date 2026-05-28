---
apiVersion: v1
kind: Namespace
metadata:
  name: vpa
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: vpa
  namespace: kube-system
spec:
  chart: vpa
  version: "${version}"
  repo: https://charts.fairwinds.com/stable
  targetNamespace: vpa
  createNamespace: true