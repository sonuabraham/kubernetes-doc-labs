# Configure Service Accounts for Pods – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/

> Runs on the default **minikube** cluster, in the `default` namespace as in the docs.
> Docs examples (**verbatim**): [build-robot.yaml](build-robot.yaml) (the docs' heredoc), [build-robot-secret.yaml](build-robot-secret.yaml),
> [pod-projected-svc-token.yaml](pod-projected-svc-token.yaml). [automount-opt-out.yaml](automount-opt-out.yaml) = the docs'
> two opt-out snippets made complete, plus two extra Pods. Not from the docs: [node-001.yaml](node-001.yaml),
> [finalizer-pod.yaml](finalizer-pod.yaml), [verify-token.py](verify-token.py).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **ServiceAccount** | The identity of a Pod: `system:serviceaccount:<ns>:<name>`, in groups `system:serviceaccounts` and `system:serviceaccounts:<ns>`. Every namespace has `default`. A Pod's `serviceAccountName` is **immutable**. |
| **Auto-mounted token** | A projected volume `kube-api-access-*` (token + `ca.crt` + `namespace`) at `/var/run/secrets/kubernetes.io/serviceaccount`. Opt out with `automountServiceAccountToken: false` on the SA or the Pod; **the Pod wins**. |
| **Bound tokens** (TokenRequest) | JWTs with `aud`, `exp` and a bound object (Pod, Secret or **Node**). They die when the object is deleted, and a Pod's token dies **60 s after its `deletionTimestamp`**. Created by `kubectl create token` or by the kubelet. |
| **Legacy token Secret** | `type: kubernetes.io/service-account-token` + annotation. Never expires and is deleted with the SA. Use only if you really need it. Usage is tracked in the label `kubernetes.io/legacy-token-last-used`. |
| **imagePullSecrets on the SA** | Copied into every new Pod that uses the SA. |
| **Issuer discovery** | `/.well-known/openid-configuration` + `/openid/v1/jwks` let external systems verify tokens **offline**. |

---

## Step 0 – a token-only kubectl
Your kubeconfig uses a client certificate, and the API server checks that **before** a bearer token. So
`kubectl --token=…` still authenticates you as `minikube-user`. To really act as a token, drop the kubeconfig:
```bash
cd tasks/configure-pod-container/configure-service-account
SRV=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority}')
kt(){ t=$1; shift; kubectl --kubeconfig=/dev/null --server=$SRV --certificate-authority=$CA --token="$t" "$@"; }
jwt(){ cut -d. -f2 | tr '_-' '/+' | { read p; while [ $(( ${#p} % 4 )) -ne 0 ]; do p="$p="; done; echo "$p" | base64 -d; }; }
```

## Lab 1 – The default ServiceAccount
```bash
kubectl run sa-default --image=busybox:1.36 -- sleep 1h
kubectl get pod sa-default -o json | jq -c '{sa:.spec.serviceAccountName, sources:[.spec.volumes[0].projected.sources[]|keys[0]]}'
#   {"sa":"default","sources":["serviceAccountToken","configMap","downwardAPI"]}
kubectl exec sa-default -- ls /var/run/secrets/kubernetes.io/serviceaccount/
#   ca.crt  namespace  token
```

## Lab 2 – More ServiceAccounts, and opting out of automount
```bash
kubectl get serviceaccounts            # NAME default  AGE …   (the docs' SECRETS column is gone in 1.3x)
kubectl apply -f build-robot.yaml
kubectl apply -f automount-opt-out.yaml   # SA build-robot: automount false + three Pods
for p in my-pod my-pod-override my-pod-inherit; do echo "$p: $(kubectl exec $p -- ls /var/run/secrets/kubernetes.io/serviceaccount 2>&1 | tr '\n' ' ')"; done
```
| Pod | Pod field | SA field | Token mounted? |
|---|---|---|---|
| my-pod (docs) | `false` | `false` | no |
| my-pod-override | `true` | `false` | **yes**: the Pod spec wins |
| my-pod-inherit | unset | `false` | no |
```bash
kubectl patch pod my-pod -p '{"spec":{"serviceAccountName":"default"}}'
#   The Pod "my-pod" is invalid: spec: Forbidden: pod updates may not change fields other than …   <- immutable
```

## Lab 3 – `kubectl create token`
```bash
T=$(kubectl create token build-robot)
echo "$T" | jwt | jq -c '{aud,iss,sub,ttl:(.exp-.iat)}'
#   {"aud":["https://kubernetes.default.svc.cluster.local"],"iss":"https://kubernetes.default.svc.cluster.local",
#    "sub":"system:serviceaccount:default:build-robot","ttl":3600}
kt "$T" auth whoami
#   Username  system:serviceaccount:default:build-robot
#   Groups    [system:serviceaccounts system:serviceaccounts:default system:authenticated]
kt "$T" get pods
#   Error from server (Forbidden): … cannot list resource "pods" …     <- authenticated, but no RBAC yet
kubectl create token build-robot --duration=48h | jwt | jq '.exp-.iat'      # 172800
kubectl create token build-robot --duration=2s
#   … spec.expirationSeconds: Invalid value: 2: may not specify a duration less than 10 minutes
kt "$(kubectl create token build-robot --audience=vault)" auth whoami
#   error: You must be logged in to the server (Unauthorized)          <- aud "vault" isn't an API audience
```

## Lab 4 – A token bound to a Node (docs, with a throwaway Node)
```bash
kubectl apply -f node-001.yaml                   # API-only Node "node-001", tainted, no kubelet
U=$(kubectl get node node-001 -o jsonpath='{.metadata.uid}')
T=$(kubectl create token build-robot --bound-object-kind Node --bound-object-name node-001 --bound-object-uid $U)
kt "$T" auth whoami | grep -E 'Username|node'
#   Username                                       system:serviceaccount:default:build-robot
#   Extra: authentication.kubernetes.io/node-name  [node-001]
kubectl delete node node-001; sleep 5
kt "$T" auth whoami                              # error: You must be logged in to the server (Unauthorized)
kubectl create token build-robot --bound-object-kind Node --bound-object-name minikube --bound-object-uid 123
#   … the UID in the bound object reference (123) does not match the UID in record …
```
If you use the token right before deleting the Node, it keeps working for a few more seconds. The API server
caches successful token authentications for about 10 s.

## Lab 5 – When does a Pod's token die? (not from the docs)
```bash
T=$(kubectl exec sa-default -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
kubectl delete pod sa-default --wait=false
# poll kt "$T" auth whoami every 10 s:
#   deletionTimestamp 03:07:01 (now + 30 s grace)
#   t+0…21s  Running → token OK
#   t+32s    Pod object gone → Unauthorized     <- the bound object no longer exists
kubectl apply -f finalizer-pod.yaml               # the same, but a finalizer keeps the Pod object around
T=$(kubectl exec sa-finalizer -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
kubectl delete pod sa-finalizer --wait=false
#   deletionTimestamp 03:07:20 (grace 5 s)
#   03:08:15  phase Failed, object still there → token OK
#   03:08:24  → Unauthorized                     <- 03:07:20 + 60 s, exactly the docs' rule
kubectl patch pod sa-finalizer --type=json -p '[{"op":"remove","path":"/metadata/finalizers"}]'
```

## Lab 6 – A long-lived token Secret (docs)
```bash
kubectl apply -f build-robot-secret.yaml
kubectl describe secrets/build-robot-secret
#   Annotations:  kubernetes.io/service-account.name: build-robot
#                 kubernetes.io/service-account.uid: b48d850d-…
#   Type:  kubernetes.io/service-account-token
#   ca.crt: 1111 bytes   namespace: 7 bytes   token: …
LT=$(kubectl get secret build-robot-secret -o jsonpath='{.data.token}' | base64 -d)
echo "$LT" | jwt | jq -c .
#   {"iss":"kubernetes/serviceaccount", …, "sub":"system:serviceaccount:default:build-robot"}   <- no exp, no aud
kt "$LT" auth whoami | grep Username
kubectl get secret build-robot-secret -o jsonpath='{.metadata.labels}'
#   {"kubernetes.io/legacy-token-last-used":"2026-11-15"}       <- set once the token is used
kubectl get sa build-robot -o jsonpath='{.secrets}'          # empty, as the docs' note says
```
It is deleted with the ServiceAccount (do this at the end, see Lab 9).

## Lab 7 – imagePullSecrets via the ServiceAccount (docs)
```bash
kubectl create secret docker-registry myregistrykey --docker-server=registry.example.com \
  --docker-username=DUMMY_USERNAME --docker-password=DUMMY_DOCKER_PASSWORD --docker-email=DUMMY_DOCKER_EMAIL
kubectl get secrets myregistrykey        # myregistrykey   kubernetes.io/dockerconfigjson   1
kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "myregistrykey"}]}'
kubectl run nginx --image=registry.example.com/nginx --restart=Never
kubectl get pod nginx -o=jsonpath='{.spec.imagePullSecrets[0].name}{"\n"}'
#   myregistrykey                         <- injected by the ServiceAccount admission plugin
kubectl delete pod nginx --now
kubectl patch serviceaccount default --type=json -p '[{"op":"remove","path":"/imagePullSecrets"}]'   # undo
```

## Lab 8 – Projected token with audience `vault` (docs) + offline verification
```bash
kubectl apply -f build-robot.yaml          # automount back on
kubectl create -f pod-projected-svc-token.yaml
kubectl exec nginx -- cat /var/run/secrets/tokens/vault-token | jwt | jq -c '{aud, ttl:(.exp-.iat), pod:."kubernetes.io".pod.name}'
#   {"aud":["vault"],"ttl":7200,"pod":"nginx"}
kubectl exec nginx -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | jwt | jq -c '{ttl:(.exp-.iat), warn:(."kubernetes.io".warnafter-.iat)}'
#   {"ttl":31536000,"warn":3607}   <- the default token is extended to 1 year (--service-account-extend-token-expiration),
#                                     but the API server logs a warning when it is used after 3607 s
```
The kubelet refreshes a projected token once it is older than 80 % of its TTL (or 24 h). Apps must re-read the file.

Issuer discovery, as an external relying party (like Vault) would use it:
```bash
kubectl get --raw /.well-known/openid-configuration | jq -c .
#   {"issuer":"https://kubernetes.default.svc.cluster.local","jwks_uri":"https://192.168.58.2:8443/openid/v1/jwks",…,"id_token_signing_alg_values_supported":["RS256"]}
kubectl get --raw /openid/v1/jwks | cat > /tmp/jwks.json
kubectl exec nginx -- cat /var/run/secrets/tokens/vault-token | python3 verify-token.py /tmp/jwks.json vault
#   signature OK (kid zDPJkSQcY1wp…)
#   aud  ['vault']  -> OK
#   exp  in 3833s  -> OK
kubectl exec nginx -- cat /var/run/secrets/tokens/vault-token | sed 's/\.[^.]*$/.AAAA/' | python3 verify-token.py /tmp/jwks.json vault
#   FAIL: bad signature
kubectl get clusterrolebinding system:service-account-issuer-discovery -o json | jq -c '{role:.roleRef.name, subjects:.subjects}'
#   {"role":"system:service-account-issuer-discovery","subjects":[{…"kind":"Group","name":"system:serviceaccounts"}]}
minikube ssh -- "sudo grep service-account /etc/kubernetes/manifests/kube-apiserver.yaml"
#   --service-account-issuer=https://kubernetes.default.svc.cluster.local
#   --service-account-key-file=/var/lib/minikube/certs/sa.pub
#   --service-account-signing-key-file=/var/lib/minikube/certs/sa.key
```
Offline checks can't see revocation, such as a deleted Pod. Only the API server (TokenReview) knows about that.

## Lab 9 – Delete the ServiceAccount (docs cleanup)
```bash
LT=$(kubectl get secret build-robot-secret -o jsonpath='{.data.token}' | base64 -d)
kubectl delete pod nginx my-pod my-pod-override my-pod-inherit --now
kubectl delete serviceaccount/build-robot
kubectl get secret build-robot-secret     # Error from server (NotFound) - the whole Secret was removed
kt "$LT" auth whoami                      # Unauthorized
```

## Useful commands
```bash
kubectl auth whoami                                        # who am I (cert user)
kubectl create token <sa> [--duration=1h] [--audience=x] [--bound-object-kind Pod|Secret|Node …]
kubectl get pods -A -o custom-columns=NS:.metadata.namespace,POD:.metadata.name,SA:.spec.serviceAccountName
kubectl get secrets -A --field-selector type=kubernetes.io/service-account-token     # find legacy tokens
```

## Cleanup
```bash
./cleanup.sh
```
