---
# Staging issuer – use during development to avoid Let's Encrypt rate limits.
# Switch cert-manager.io/cluster-issuer annotations to "letsencrypt-staging"
# to get untrusted (but functional) certificates for testing.
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: ${acme_email}
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik
---
# Production issuer – issues trusted certificates recognised by all browsers.
# cert-manager stores the ACME account key in the secret named below and will
# reuse it across certificate renewals.
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: ${acme_email}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik
