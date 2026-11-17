# Accessing Clusters – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/access-application-cluster/access-cluster/

> Runs against the default **minikube** cluster from your machine. Files: [default-token-secret.yaml](default-token-secret.yaml) (docs, **verbatim**).
> Not from the docs: [list_namespaces.py](list_namespaces.py) + [run-python-client.sh](run-python-client.sh) (Python client with your kubeconfig, run in a container).
>
> **Found:** "replacing localhost with `[::1]` for IPv6" doesn't work as written. `kubectl proxy` listens on `127.0.0.1` only.
> `--address=::1` fails (`too many colons in address`), and `--address='[::1]'` answers **Forbidden** until you also set `--accept-hosts='^::1$'`.
> The long-lived token Secret works, but it is the legacy way (`kubectl create token` gives short-lived tokens).

## Key ideas (read first)

| Way | Locates the API by | Authenticates with | TLS check |
|---|---|---|---|
| `kubectl` | kubeconfig `server:` | kubeconfig user (minikube: client cert) | kubeconfig CA |
| `kubectl proxy` | kubeconfig | adds your credentials | proxy verifies; client→proxy is plain HTTP on localhost |
| curl + token | `kubectl config view` | `Authorization: Bearer <token>` | `--cacert` (docs use `--insecure`) |
| client library | same kubeconfig | same | same |

---

## Lab 1 – Where is the cluster? (docs)
```bash
cd tasks/access-application-cluster/access-cluster
kubectl config view --minify
#   certificate-authority: /home/<you>/.minikube/ca.crt
#   server: https://192.168.58.2:8443
#   user: client-certificate: …/profiles/minikube/client.crt   client-key: …/client.key
```

## Lab 2 – kubectl proxy (docs)
```bash
kubectl proxy --port=8080 &
curl http://localhost:8080/api/
#   { "kind": "APIVersions", "versions": [ "v1" ], "serverAddressByClientCIDRs": [ { …, "serverAddress": "192.168.58.2:8443" } ] }
curl 'http://[::1]:8080/api/'                    # Failed to connect to ::1 port 8080   <- listens on 127.0.0.1:8080 only
kill %1
```
IPv6 (not from the docs):
```bash
kubectl proxy --port=8080 --address=::1          # error: listen tcp: address ::1:8080: too many colons in address
kubectl proxy --port=8080 --address='[::1]' &    # curl 'http://[::1]:8080/api/' → Forbidden   (Host header not accepted)
kill %1
kubectl proxy --port=8080 --address='[::1]' --accept-hosts='^::1$' &     # → 200
kill %1
```
The default `--accept-hosts` is `^localhost$,^127\.0\.0\.1$,^\[::1\]$`, but the host is checked **without** brackets
(`'^\[::1\]$'` → 403, `'^::1$'` → 200), so the IPv6 default never matches.

## Lab 3 – Without the proxy: token + curl (docs)
```bash
kubectl apply -f default-token-secret.yaml
while ! kubectl describe secret default-token | grep -E '^token' >/dev/null; do echo "waiting for token..." >&2; sleep 1; done
APISERVER=$(kubectl config view --minify | grep server | cut -f 2- -d ":" | tr -d " ")      # https://192.168.58.2:8443
TOKEN=$(kubectl describe secret default-token | grep -E '^token' | cut -f2 -d':' | tr -d " ")
curl $APISERVER/api --header "Authorization: Bearer $TOKEN" --insecure                      # APIVersions …
APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
TOKEN=$(kubectl get secret default-token -o jsonpath='{.data.token}' | base64 --decode)
curl $APISERVER/api --header "Authorization: Bearer $TOKEN" --insecure                      # same
```
Beyond the docs:
```bash
curl -s $APISERVER/api -H "Authorization: Bearer $TOKEN" --cacert ~/.minikube/ca.crt | jq .kind     # "APIVersions"  <- no --insecure needed
curl -s $APISERVER/api                           # SSL certificate … unable to get local issuer certificate
echo $TOKEN | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq -c '{iss,sub,exp}'
#   {"iss":"kubernetes/serviceaccount","sub":"system:serviceaccount:default:default","exp":null}   <- never expires
curl -s $APISERVER/api/v1/namespaces/default/pods -H "Authorization: Bearer $TOKEN" --cacert ~/.minikube/ca.crt | jq -r .message
#   pods is forbidden: User "system:serviceaccount:default:default" cannot list resource "pods" …
curl -s $APISERVER/api/v1/namespaces/default/pods --cert ~/.minikube/profiles/minikube/client.crt \
  --key ~/.minikube/profiles/minikube/client.key --cacert ~/.minikube/ca.crt | jq -r .kind        # PodList  (= kubectl's identity)
kubectl get secret default-token -o jsonpath='{.metadata.labels}'
#   {"kubernetes.io/legacy-token-last-used":"2026-11-17"}   <- unused legacy tokens get cleaned up eventually
```

## Lab 4 – Client library outside the cluster (docs: Python)
```bash
./run-python-client.sh
#   server: https://192.168.58.2:8443
#   namespace: default / kube-node-lease / kube-public / kube-system
```
`config.load_kube_config()` reads the same kubeconfig as kubectl. Inside a Pod you use `load_incluster_config()` instead
([access-api-from-pod](../../run-application/access-api-from-pod/)).

## Cleanup
```bash
./cleanup.sh
```
