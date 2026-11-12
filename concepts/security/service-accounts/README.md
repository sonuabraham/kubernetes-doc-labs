# Service Accounts – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/service-accounts/

> The page's one manifest is **verbatim** in [04-enforce-mountable-secrets-sa.yaml](04-enforce-mountable-secrets-sa.yaml) (namespace `my-namespace`). [00-setup.yaml](00-setup.yaml) creates SA `pod-reader` with RBAC, including a cross-namespace grant. [01-pods.yaml](01-pods.yaml) has a curl Pod using that SA and a Pod with no token.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **ServiceAccount** | A **non-human** identity (`system:serviceaccount:<ns>:<name>`). Namespaced, lightweight, API-managed (unlike human users). |
| **default SA** | Every namespace gets one. Pods without `serviceAccountName` use it. It has **no** extra permissions beyond basic discovery. |
| **Token in Pods** | A **projected, short-lived, audience- and Pod-bound** JWT at `/var/run/secrets/kubernetes.io/serviceaccount/` (`token`, `ca.crt`, `namespace`), refreshed by the kubelet. Opt out with `automountServiceAccountToken: false`. |
| **Permissions** | RBAC Role/ClusterRole bindings to the SA. Cross-namespace: a RoleBinding **in the target namespace** naming the SA. |
| **Manual tokens** | `kubectl create token` (TokenRequest API): choose duration, audience, bound object. Long-lived Secret tokens are legacy (`../../configuration/secret`, Lab 2). |
| **Validation** | API server: built-in. Others: **TokenReview** API, or offline via **OIDC discovery** (`/.well-known/openid-configuration` + JWKS). |
| **Node audience restriction** (`ServiceAccountNodeAudienceRestriction`, beta, on) | A kubelet may only request tokens for audiences the Pod actually uses (projected volumes, CSI drivers…). |
| **enforce-mountable-secrets** | **Deprecated** since v1.32: the SA's `secrets` list restricts what its Pods can mount. Use namespaces instead. |
| **Alternatives** | Your own token webhook, SPIFFE/SPIRE, cloud workload identity, X.509 via `podCertificate` (`../../storage/projected-volumes`). |

---

## Step 1
```bash
cd concepts/security/service-accounts
kubectl apply -f 00-setup.yaml -f 01-pods.yaml
kubectl get sa -n sa-demo                              # default (automatic), pod-reader
```

## Lab 1 – The token inside a Pod
```bash
kubectl get pod api-client -n sa-demo -o jsonpath='{.spec.volumes[0].projected.sources}'
#   [{"serviceAccountToken":{"expirationSeconds":3607,"path":"token"}},
#    {"configMap":{"name":"kube-root-ca.crt",...}}, {"downwardAPI":{... metadata.namespace ...}}]   <- injected by admission
kubectl exec api-client -n sa-demo -- ls /var/run/secrets/kubernetes.io/serviceaccount     # ca.crt namespace token
kubectl exec no-token -n sa-demo -- ls /var/run/secrets/kubernetes.io/serviceaccount       # No such file  (automount false)
```

## Lab 2 – Permissions, including cross-namespace
```bash
for p in /api/v1/namespaces/sa-demo/pods /api/v1/namespaces/sa-other/pods /api/v1/namespaces/sa-demo/secrets /api/v1/namespaces/kube-system/pods; do
  printf '%-40s ' $p
  kubectl exec api-client -n sa-demo -- sh -c "curl -s -o /dev/null -w '%{http_code}\n' --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    -H \"Authorization: Bearer \$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)\" https://kubernetes.default.svc$p"
done
#   /api/v1/namespaces/sa-demo/pods          200   <- Role pod-reader
#   /api/v1/namespaces/sa-other/pods         200   <- RoleBinding in sa-other → ClusterRole view
#   /api/v1/namespaces/sa-demo/secrets       403
#   /api/v1/namespaces/kube-system/pods      403
```

## Lab 3 – Tokens on demand and TokenReview
```bash
review(){ kubectl create -o json -f - <<EOF | jq -c '.status | {authenticated, user: .user.username, aud: .audiences, error}'
apiVersion: authentication.k8s.io/v1
kind: TokenReview
spec: {token: "$1" $( [ -n "${2:-}" ] && echo ", audiences: [\"$2\"]")}
EOF
}
T=$(kubectl create token pod-reader -n sa-demo --duration=10m) ; review "$T"
#   {"authenticated":true,"user":"system:serviceaccount:sa-demo:pod-reader","aud":["https://kubernetes.default.svc.cluster.local"]}
V=$(kubectl create token pod-reader -n sa-demo --audience=vault)
review "$V"          # error: token audiences ["vault"] is invalid for the target audiences ["https://kubernetes.default.svc.cluster.local"]
review "$V" vault    # authenticated: true   <- a token for Vault can't be replayed against the API server
```

## Lab 4 – Pod-bound tokens die with the Pod
```bash
kubectl run bound -n sa-demo --image=busybox:1.36 -- sleep 3600
B=$(kubectl create token default -n sa-demo --bound-object-kind Pod --bound-object-name bound)
review "$B"                                      # authenticated: true
kubectl delete pod bound -n sa-demo
review "$B"                                      # error: service account token has been invalidated
```
With `--force --grace-period=0` the review still succeeded right after the delete: the object wasn't gone yet. Once it was, the token was rejected.

## Lab 5 – OIDC discovery (validate tokens without calling TokenReview)
```bash
kubectl get --raw /.well-known/openid-configuration | jq -c '{issuer, jwks_uri}'
#   {"issuer":"https://kubernetes.default.svc.cluster.local","jwks_uri":"https://192.168.58.2:8443/openid/v1/jwks"}
kubectl get --raw /openid/v1/jwks | jq -c '.keys[0] | {kty, alg, use}'       # {"kty":"RSA","alg":"RS256","use":"sig"}
kubectl create token pod-reader -n sa-demo | python3 -c 'import sys,base64,json;p=sys.stdin.read().split(".")[1];p+="="*(-len(p)%4);print(base64.urlsafe_b64decode(p).decode())' | jq -c '{iss,sub,aud}'
```
External systems (Vault, cloud IAM) fetch the JWKS and verify signature, `iss`, `aud` and `exp` themselves.

## Lab 6 – Node audience restriction
```bash
kubectl run np -n sa-demo --image=busybox:1.36 -- sleep 3600
U=$(kubectl get pod np -n sa-demo -o jsonpath='{.metadata.uid}')
NODE="--as system:node:minikube --as-group system:nodes"
kubectl create token default -n sa-demo --audience=my-random-aud --bound-object-kind Pod --bound-object-name np --bound-object-uid $U $NODE
#   forbidden: system:node:minikube is not authorized to request tokens for audience "my-random-aud"
kubectl create token default -n sa-demo --bound-object-kind Pod --bound-object-name np --bound-object-uid $U $NODE    # OK (API audience)
```
A compromised node can't mint tokens for audiences its Pods don't use. (Without `--bound-object-uid` the node request is refused earlier: "node requested token with a pod binding without a uid".)

## Lab 7 – enforce-mountable-secrets (deprecated, docs SA)
```bash
kubectl create ns my-namespace
kubectl apply -f 04-enforce-mountable-secrets-sa.yaml
#   Warning: metadata.annotations[kubernetes.io/enforce-mountable-secrets]: deprecated in v1.32+; prefer separate namespaces ...
kubectl create secret generic allowed-secret -n my-namespace --from-literal=k=v
kubectl create secret generic other-secret -n my-namespace --from-literal=k=v
kubectl patch sa my-serviceaccount -n my-namespace -p '{"secrets":[{"name":"allowed-secret"}]}'
# Pods using my-serviceaccount that mount each secret:
#   m-allowed-secret: created
#   m-other-secret:   forbidden: volume with secret.secretName="other-secret" is not allowed because service account my-serviceaccount does not reference that secret
```

---

## Useful commands
```bash
kubectl create sa <n> ; kubectl create token <sa> [--duration=1h] [--audience=x] [--bound-object-kind Pod --bound-object-name p]
kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa> -n <ns>
kubectl get pod <p> -o jsonpath='{.spec.serviceAccountName}'
```

## Cleanup
```bash
./cleanup.sh
```
