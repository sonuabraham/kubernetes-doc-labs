# Configure the Aggregation Layer – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/extend-kubernetes/configure-aggregation-layer/

> Labs 1–2 run on the default **minikube** cluster; Lab 3 on a throwaway profile **`agg-lab`**. The extension API server itself (a small
> Python "toy" server that trusts the front-proxy headers) comes from the concept lab
> [concepts/…/apiserver-aggregation](../../../concepts/extend-kubernetes/api-extension/apiserver-aggregation/), which also covers the request
> flow, RBAC, and header spoofing. Files here (not from the docs, except the APIService shape): [apiservice-port-1234.yaml](apiservice-port-1234.yaml)
> (the docs' "port 1234" example, filled in), [setup-toy-1234.sh](setup-toy-1234.sh), [ca-reuse-lab.sh](ca-reuse-lab.sh).
>
> **Found:** the "CA Reusage and Conflicts" section says that if `--client-ca-file` and `--requestheader-client-ca-file` share a CA,
> normal client-cert users and kubelets **fail** to authenticate. In v1.37 they **don't**: `minikube-user` still works (Lab 3). The real problem
> is worse: **any certificate from the cluster CA with CN `front-proxy-client` can then claim to be any user/group** via `X-Remote-User`/
> `X-Remote-Group`, including `system:masters`. So do keep the CAs separate, but for that reason.

## Key ideas (read first)

| Flag (kube-apiserver) | minikube value | Role |
|---|---|---|
| `--proxy-client-cert-file` / `-key-file` | `front-proxy-client.crt` (CN `front-proxy-client`, issuer `front-proxy-ca`) | the aggregator's client cert towards **all** extension servers |
| `--requestheader-client-ca-file` | `front-proxy-ca.crt` (its own CA) | which CA may sign proxy certs |
| `--requestheader-allowed-names` | `front-proxy-client` | allowed CNs (empty = any CN) |
| `--requestheader-username/group-headers`, `--requestheader-extra-headers-prefix` | `X-Remote-User`, `X-Remote-Group`, `X-Remote-Extra-` | headers carrying the original identity |
| `--client-ca-file` | `ca.crt` (minikubeCA) | normal x509 users, a **different** CA |
| `--enable-aggregator-routing` | not set | only needed when no kube-proxy runs on the API server host |

All of it is published in `kube-system/extension-apiserver-authentication`. Extension servers read it with the Role
`extension-apiserver-authentication-reader` and check users with `system:auth-delegator` (SubjectAccessReviews).

---

## Lab 1 – What minikube (kubeadm) configures
```bash
cd tasks/extend-kubernetes/configure-aggregation-layer
minikube ssh -- "sudo grep -E 'requestheader|proxy-client|client-ca-file|aggregator-routing' /etc/kubernetes/manifests/kube-apiserver.yaml"
#   --client-ca-file=/var/lib/minikube/certs/ca.crt
#   --proxy-client-cert-file=/var/lib/minikube/certs/front-proxy-client.crt
#   --proxy-client-key-file=/var/lib/minikube/certs/front-proxy-client.key
#   --requestheader-allowed-names=front-proxy-client
#   --requestheader-client-ca-file=/var/lib/minikube/certs/front-proxy-ca.crt
#   --requestheader-extra-headers-prefix=X-Remote-Extra-
#   --requestheader-group-headers=X-Remote-Group
#   --requestheader-username-headers=X-Remote-User
kubectl -n kube-system get cm extension-apiserver-authentication -o json | jq -r '.data | keys[]'
#   client-ca-file  requestheader-allowed-names  requestheader-client-ca-file  requestheader-extra-headers-prefix  …group-headers  …username-headers
minikube ssh -- 'for f in ca.crt front-proxy-ca.crt front-proxy-client.crt; do sudo openssl x509 -in /var/lib/minikube/certs/$f -noout -subject -issuer; done'
#   subject=CN = minikubeCA           issuer=CN = minikubeCA
#   subject=CN = front-proxy-ca       issuer=CN = front-proxy-ca        <- separate CA
#   subject=CN = front-proxy-client   issuer=CN = front-proxy-ca        (Extended Key Usage: TLS Web Client Authentication)
kubectl -n kube-system get rolebinding -o wide | grep extension-apiserver-authentication-reader
#   metrics-server-auth-reader   Role/extension-apiserver-authentication-reader   …   kube-system/metrics-server
kubectl get clusterrolebinding -o wide | grep auth-delegator
#   metrics-server:system:auth-delegator   ClusterRole/system:auth-delegator   …   kube-system/metrics-server
```

## Lab 2 – Register an APIService on port 1234 (docs "Contacting the extension apiserver")
```bash
./setup-toy-1234.sh                       # concept lab's deploy.sh, then Service port → 1234, APIService port: 1234
kubectl get apiservice v1.toys.example.com
#   v1.toys.example.com   agg-demo/toy-apiserver   True
kubectl get --raw /apis/toys.example.com/v1/namespaces/default/whoamis | jq -c '.items[0] | {user, groups, via}'
#   {"user":"minikube-user","groups":["system:masters","system:authenticated"],"via":"front-proxy-client"}
```
Break it on purpose (not from the docs):
```bash
kubectl patch apiservice v1.toys.example.com --type=merge -p '{"spec":{"service":{"port":443}}}'
kubectl get apiservice v1.toys.example.com -o jsonpath='{.status.conditions[0].reason}: {.status.conditions[0].message}'
#   ServicePortError: service/toy-apiserver in "agg-demo" is not listening on port 443
kubectl get --raw /apis/toys.example.com/v1        # Error from server (ServiceUnavailable): the server is currently unable to handle the request
# port back to 1234, but caBundle = minikube's cluster CA (wrong CA):
#   FailedDiscoveryCheck: … tls: failed to verify certificate: x509: certificate signed by unknown authority
```
Delete it before Lab 3: `../../../concepts/extend-kubernetes/api-extension/apiserver-aggregation/cleanup.sh`.

## Lab 3 – Reusing the cluster CA as requestheader CA (docs warning, tested)
```bash
./ca-reuse-lab.sh start      # stops minikube, starts agg-lab with --requestheader-client-ca-file=…/ca.crt (same as --client-ca-file)
kubectl --context agg-lab get nodes        # works: normal users are NOT locked out
./ca-reuse-lab.sh probe
#   1) normal client cert (CN=minikube-user):                    "minikube-user"  ["system:masters",…]
#   2) same cert + X-Remote-User: mallory:                       "minikube-user"  <- headers ignored: CN not allowed
#   3) cluster-CA cert CN=front-proxy-client
#      + X-Remote-User: mallory, X-Remote-Group: system:masters: "mallory"  ["system:masters","system:authenticated"]   <- impersonation!
#   4) same cert, no headers:                                    "front-proxy-client"
./ca-reuse-lab.sh delete     # deletes agg-lab, starts minikube again
```
With separate CAs, case 3 is impossible unless someone has the front-proxy CA key. With a shared CA, anyone who can get a
cluster-CA certificate named `front-proxy-client` (a careless CSR approval is enough) owns the cluster.

## Cleanup
```bash
./cleanup.sh
```
