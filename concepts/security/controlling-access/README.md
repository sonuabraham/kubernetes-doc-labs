# Controlling Access to the Kubernetes API – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/controlling-access/

> The page's two JSON blocks are **verbatim**: [abac-policy-excerpt.json](abac-policy-excerpt.json) (ABAC, which needs an API-server policy file, so it's re-expressed in RBAC in [00-setup.yaml](00-setup.yaml)) and [subjectaccessreview-v1beta1.json](subjectaccessreview-v1beta1.json). [make-bob.sh](make-bob.sh) makes a real **x509 user `bob`** through the CSR API, with a kubeconfig in `generated/` (gitignored).

## Key ideas (read first)

Every request passes these stages in order. The first failure stops it.

| Stage | What happens | Failure |
|---|---|---|
| **Transport** | TLS on the API port (here 8443, usually 443). The server cert is signed by the cluster CA. Optional client certs. | TLS error |
| **Authentication** | One or more authenticators (client certs, bearer/SA tokens, OIDC, webhook, auth proxy). The first success gives username, UID, groups. No match → `system:anonymous` (if enabled), else **401**. | 401 |
| **Authorization** | Each authorizer (**Node**, **RBAC**, ABAC, Webhook) says allow / deny / no opinion. Any allow wins. Attributes: user, group, verb, resource, namespace, API group… | 403 |
| **Admission control** | **Mutating** then **validating** plugins/webhooks/policies. They see the object content. Reads aren't admitted. | 403 / 400 |
| **Validation + persistence** | Schema validation, then etcd. | 422 |
| **Auditing** | Records each request at the configured stages and levels. | — |

---

## Step 1 – A real user called bob
```bash
cd concepts/security/controlling-access
./make-bob.sh
#   subject=O=caribou-devs, CN=bob       <- CN = username, O = groups
#   issuer=CN=minikubeCA
B="--kubeconfig generated/bob.kubeconfig"
```

## Lab 1 – Transport
```bash
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo | openssl s_client -connect ${SERVER#https://} 2>/dev/null | openssl x509 -noout -ext subjectAltName
#   DNS:minikubeCA, DNS:control-plane.minikube.internal, DNS:kubernetes.default.svc.cluster.local, DNS:kubernetes.default.svc, ...
```
The same cert serves clients outside (`192.168.58.2:8443`) and inside (`kubernetes.default.svc`) the cluster.

## Lab 2 – Authentication
```bash
kubectl $B auth whoami
#   Username  bob
#   Groups    [caribou-devs system:authenticated]
#   Extra: authentication.kubernetes.io/credential-id  [X509SHA256=de9e…]
curl -sk -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer nonsense' $SERVER/api/v1/namespaces     # 401
```
There's no "User" object: bob exists only because the cluster CA signed a cert saying so.

## Lab 3 – Authorization (the docs' ABAC rule, done with RBAC)
```bash
kubectl create namespace projectCaribou
#   Invalid value: "projectCaribou": a lowercase RFC 1123 label ...      <- the docs' name can't be a namespace
kubectl create namespace projectcaribou
kubectl $B get pods
#   Forbidden: User "bob" cannot list resource "pods" ... in the namespace "projectcaribou"     (authenticated, not authorized)
kubectl apply -f 00-setup.yaml          # Role pod-reader (get/list/watch) + RoleBinding to User bob, + admission objects
kubectl $B get pods                     # No resources found in projectcaribou namespace.
kubectl $B run x --image=busybox:1.36   # Forbidden: ... cannot create resource "pods"   <- "readonly": true
```

## Lab 4 – Asking the authorizer (SubjectAccessReview)
```bash
kubectl create --raw /apis/authorization.k8s.io/v1beta1/subjectaccessreviews -f subjectaccessreview-v1beta1.json
#   NotFound      <- authorization.k8s.io/v1beta1 was removed (v1.22); the docs JSON shows the webhook payload shape
kubectl create -o json -f - <<'Y' | jq -c .status
apiVersion: authorization.k8s.io/v1
kind: SubjectAccessReview
spec:
  user: bob
  groups: ["caribou-devs"]
  resourceAttributes: {namespace: projectcaribou, verb: get, resource: pods}
Y
#   {"allowed":true,"reason":"RBAC: allowed by RoleBinding \"bob-reads-pods/projectcaribou\" of Role \"pod-reader\" to User \"bob\""}
#   (same with verb: delete → {"allowed":false})
kubectl auth can-i --list --as bob -n projectcaribou
```
A **Webhook** authorizer receives exactly such a SubjectAccessReview and answers `allowed`.

## Lab 5 – Admission: mutate, then validate
```bash
for i in 1 2 3; do kubectl run p$i -n projectcaribou --image=busybox:1.36 -- sleep 3600; done
#   pod/p1 created
#   pod/p2 created
#   Error from server (Forbidden): pods "p3" is forbidden: exceeded quota: max-pods, requested: pods=1, used: pods=2, limited: pods=2
kubectl get pod p1 -n projectcaribou -o jsonpath='{.spec.containers[0].resources}{"\n"}{.metadata.annotations}{"\n"}'
#   {"limits":{"cpu":"200m","memory":"64Mi"},"requests":{"cpu":"100m","memory":"32Mi"}}
#   {"kubernetes.io/limit-ranger":"LimitRanger plugin set: cpu, memory request for container p1; cpu, memory limit for container p1"}
```
The admin passed authn and authz, but **ResourceQuota** (validating admission) still said no. **LimitRanger** (mutating) quietly rewrote the Pod.

## Lab 6 – Validation and auditing
```bash
kubectl run Bad_Name -n projectcaribou --image=busybox:1.36
#   The Pod "Bad_Name" is invalid: metadata.name: Invalid value ...      (422, after admission)
```
Auditing is **off** on minikube (no `--audit-log-path`, see `../cloud-native-security`). With an audit policy every stage above would be recorded (RequestReceived → ResponseComplete) with user, verb and decision.

---

## Useful commands
```bash
kubectl auth whoami ; kubectl auth can-i <verb> <resource> [--as user] [-n ns] ; kubectl auth can-i --list
kubectl get csr ; kubectl certificate approve|deny <csr>
kubectl get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[]' | grep -E 'authorization|admission|audit|anonymous'
```

## Cleanup
```bash
./cleanup.sh       # namespace, CSR, generated/ (bob's key)
```
