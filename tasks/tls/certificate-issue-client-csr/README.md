# Issue a Certificate for a Kubernetes API Client Using a CertificateSigningRequest – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/tls/certificate-issue-client-csr/

> Runs on the default **minikube** cluster. Files (docs, **verbatim**): [myuser.yaml](myuser.yaml), [role.yaml](role.yaml), [rolebinding.yaml](rolebinding.yaml).
> The docs' `kubectl config set-credentials/set-context` steps change your kubeconfig; this lab first copies it to `./kubeconfig-lab` and sets
> `KUBECONFIG` to that, so `~/.kube/config` stays untouched. Key, CSR, cert and lab kubeconfig are gitignored and removed by [cleanup.sh](cleanup.sh).
>
> **Found:**
> 1. `myuser.yaml`'s embedded `request` is a CSR for **`CN=angela`**, not myuser, and for a key you don't have. Applied as is, it gets
>    approved and issued, but the cert is useless to you. Put your own `myuser.csr` in (as the inline heredoc does).
> 2. `kubectl config set-context myuser --cluster=kubernetes` assumes a cluster entry named `kubernetes`. On minikube it is `minikube`, and the
>    context then fails with `The connection to the server localhost:8080 was refused`.
> 3. The page doesn't mention it: `usages` other than `client auth` aren't refused on create. The CSR can even be approved, and then the signer marks it
>    **Failed** (`invalid usage for client certificate: server auth`).

## Key ideas (read first)

| Step | Meaning |
|---|---|
| Key + PKCS#10 CSR | `CN` = username, `O` = groups (several `O=` allowed) |
| CertificateSigningRequest | `signerName: kubernetes.io/kube-apiserver-client`, `usages: [client auth]`, `expirationSeconds` ≥ 600 |
| Approve | `kubectl certificate approve` (needs `approve` on the signer) → kube-controller-manager signs with the **cluster CA** |
| Use | kubeconfig user with cert + key → authenticated as `CN`; authorization still needs RBAC |

---

## Lab 1 – Key, CSR, approve (docs)
```bash
cd tasks/tls/certificate-issue-client-csr
kubectl config view --minify --flatten --context minikube > kubeconfig-lab && export KUBECONFIG=$PWD/kubeconfig-lab
openssl genrsa -out myuser.key 3072
openssl req -new -key myuser.key -out myuser.csr -subj "/CN=myuser"
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: myuser # example
spec:
  request: $(cat myuser.csr | base64 | tr -d "\n")
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400  # one day
  usages:
  - client auth
EOF
kubectl get csr myuser
#   myuser   1s   kubernetes.io/kube-apiserver-client   minikube-user   24h   Pending
kubectl certificate approve myuser
kubectl get csr myuser                 # … Approved,Issued
kubectl get csr myuser -o jsonpath='{.status.certificate}'| base64 -d > myuser.crt
openssl x509 -in myuser.crt -noout -subject -issuer -startdate -enddate -ext extendedKeyUsage
#   subject=CN=myuser
#   issuer=CN=minikubeCA                       <- the cluster CA
#   notBefore=Nov 18 11:21:49 2026 GMT         <- backdated ~5 min (clock skew allowance)
#   notAfter=Nov 19 11:21:49 2026 GMT          <- expirationSeconds: 86400
#   X509v3 Extended Key Usage: TLS Web Client Authentication
```

## Lab 2 – kubeconfig and RBAC (docs)
```bash
kubectl config set-credentials myuser --client-key=myuser.key --client-certificate=myuser.crt --embed-certs=true
kubectl config set-context myuser --cluster=kubernetes --user=myuser
kubectl --context myuser auth whoami
#   The connection to the server localhost:8080 was refused …          <- no cluster "kubernetes" here (Found #2)
kubectl config set-context myuser --cluster=minikube --user=myuser
kubectl --context myuser auth whoami
#   Username   myuser
#   Groups     [system:authenticated]
kubectl --context myuser get pods
#   Error from server (Forbidden): pods is forbidden: User "myuser" cannot list resource "pods" …
kubectl create role developer --verb=create --verb=get --verb=list --verb=update --verb=delete --resource=pods
kubectl create rolebinding developer-binding-myuser --role=developer --user=myuser
kubectl --context myuser get pods                      # No resources found in default namespace.
kubectl --context myuser get deployments               # Forbidden (only pods were granted)
```
`role.yaml` / `rolebinding.yaml` are the same objects as the two `kubectl create` commands (rules compared: identical).

## Lab 3 – Variations (not from the docs)
```bash
kubectl delete csr myuser
kubectl apply -f myuser.yaml --server-side && kubectl certificate approve myuser
kubectl get csr myuser -o jsonpath='{.status.certificate}' | base64 -d | openssl x509 -noout -subject
#   subject=CN=angela                                 <- Found #1; and it doesn't match myuser.key
# expirationSeconds: 300:
#   … spec.expirationSeconds: Invalid value: 300: may not specify a duration less than 600 seconds (10 minutes)
openssl req -new -key myuser.key -out grp.csr -subj "/CN=myuser/O=developers"     # → CSR myuser-dev, approve, use:
#   Username  myuser
#   Groups    [developers system:authenticated]      <- O= becomes a group
# usages: [server auth] with the client signer → approved, then:
#   Failed: invalid usage for client certificate: server auth
```

## Cleanup
```bash
./cleanup.sh && unset KUBECONFIG
```
