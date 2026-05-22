%{ if hubble_ingress_hostname != "" ~}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
%{if enable_cert_manager && acme_email != ""~}
    cert-manager.io/cluster-issuer: letsencrypt-${issuer_environment}
%{endif~}
  name: hubble-ui
  namespace: kube-system
spec:
  ingressClassName: traefik
  rules:
  - host: ${hubble_ingress_hostname}
    http:
      paths:
      - backend:
          service:
            name: hubble-ui
            port:
              number: 80
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - ${hubble_ingress_hostname}
    secretName: hubble-ui-tls
%{endif~}
