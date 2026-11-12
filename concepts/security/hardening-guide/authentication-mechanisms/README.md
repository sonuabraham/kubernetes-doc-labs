# Hardening Guide – Authentication Mechanisms – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/hardening-guide/authentication-mechanisms/

> A guidance page (no YAML). [check-authn.sh](check-authn.sh) reports which mechanisms your API server has enabled. Two demos show the biggest gotchas: [demo-x509-no-revocation.sh](demo-x509-no-revocation.sh) and [demo-bootstrap-token.sh](demo-bootstrap-token.sh). Keys go to `generated/` (gitignored).

## Key ideas (read first)

| Mechanism | Risk (from the page) | Recommended for |
|---|---|---|
| **X.509 client certs** | **No revocation**. Group membership is baked into the cert. Private keys are often on disk. Long lifetimes are common. | System components only (kubelet, controllers), not humans |
| **Static token file** | Plaintext on control-plane disk, changes need an API server restart, no expiry or lockout | Nothing (avoid) |
| **Bootstrap tokens** | Shared, guessable format, intended for node join only | Node bootstrap, short-lived |
| **ServiceAccount Secret tokens** | **Never expire**, stored in Secrets | Avoid; use TokenRequest |
| **TokenRequest tokens** | Short-lived, audience- and object-bound; still bearer tokens | Workloads → API |
| **OIDC** | Needs a trustworthy IdP. Avoid running the IdP **in** the cluster it guards. | **Human users** |
| **Webhook token** | Webhook must be secured. The API server trusts its answer. | Integrations (cloud IAM) |
| **Authenticating proxy** | Anyone able to reach the API with a cert accepted by `--requestheader-client-ca-file` can claim **any** identity via `X-Remote-User`. Restrict `--requestheader-allowed-names`. | Aggregated APIs / special setups |

---

## Lab 1 – What is enabled here?
```bash
cd concepts/security/hardening-guide/authentication-mechanisms
./check-authn.sh
```
Measured on minikube:
```
X.509 client certs      --client-ca-file                  /var/lib/minikube/certs/ca.crt
Static token file       --token-auth-file                 (not set)                       <- good
Bootstrap tokens        --enable-bootstrap-token-auth     true
ServiceAccount tokens   --service-account-issuer          https://kubernetes.default.svc.cluster.local
                        --service-account-max-token-expiration (not set)
OIDC                    --oidc-issuer-url / --authentication-config  (not set)            <- humans use the admin cert
Webhook token           (not set)
Authenticating proxy    --requestheader-client-ca-file    /var/lib/minikube/certs/front-proxy-ca.crt
                        --requestheader-allowed-names     front-proxy-client              <- restricted, as recommended
Anonymous               --anonymous-auth                  (not set = enabled)
```
Your own kubeconfig on minikube is an X.509 cert in group `system:masters`, which is exactly what the page warns against for humans.

## Lab 2 – X.509 can't be revoked
```bash
./demo-x509-no-revocation.sh
#   1) carol's cert:      Username carol   Groups [carol-team system:authenticated]
#   2) CSR deleted ->     Username carol                 <- still authenticates
#   3) cert expiry: notAfter=…                            <- valid until then, whatever you do in the API
```
The only levers: remove RBAC bindings for `carol` / `carol-team` (but every group in the cert stays valid), keep lifetimes short (`expirationSeconds`), or rotate the cluster CA, which breaks everything.

## Lab 3 – Bootstrap tokens are credentials
```bash
./demo-bootstrap-token.sh
#   Username  system:bootstrap:lab123
#   Groups    [system:bootstrappers system:bootstrappers:lab system:authenticated]
#   can it create CSRs (to join as a node)? no      <- kubeadm only grants that to system:bootstrappers:kubeadm:default-node-token
```
Format `[a-z0-9]{6}.[a-z0-9]{16}`, stored as a Secret in `kube-system`. Keep them short-lived (the docs' example token from 2020 was cleaned up within seconds, see `../../../configuration/secret` Lab 3).

---

## Useful commands
```bash
kubectl auth whoami
kubectl get csr ; kubectl get secrets -n kube-system --field-selector type=bootstrap.kubernetes.io/token
kubectl config view --minify --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -noout -subject -enddate
```

## Cleanup
```bash
./cleanup.sh
```
