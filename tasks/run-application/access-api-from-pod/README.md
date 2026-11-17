# Accessing the Kubernetes API from a Pod – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/run-application/access-api-from-pod/

> Runs on the default **minikube** cluster, `default` namespace. Files: [direct-access.sh](direct-access.sh) (the docs' commands, **verbatim**).
> Not from the docs: [curl-pod.yaml](curl-pod.yaml), [rbac-pod-reader.yaml](rbac-pod-reader.yaml),
> [proxy-sidecar-pod.yaml](proxy-sidecar-pod.yaml) (the `kubectl proxy` sidecar the page only describes),
> [python-client.yaml](python-client.yaml) (official Python client, `load_incluster_config()`).
>
> The page's commands work as written. They only call `/api`, which any authenticated identity may read. Real calls also need **RBAC**
> (Lab 2). The script sets `NAMESPACE` but never uses it.

## Key ideas (read first)

| Piece | Where |
|---|---|
| API address | env `KUBERNETES_SERVICE_HOST`/`_PORT` (= the `kubernetes` Service ClusterIP) or DNS `kubernetes.default.svc` |
| Token | `/var/run/secrets/kubernetes.io/serviceaccount/token` (bound, auto-rotated) |
| CA | `…/ca.crt`; namespace in `…/namespace` |
| Permissions | the ServiceAccount has **none** beyond discovery; add a Role/RoleBinding |
| Options | client library (in-cluster config) · `kubectl proxy` sidecar · raw HTTPS + token |

---

## Lab 1 – Raw HTTPS with the token (docs)
```bash
cd tasks/run-application/access-api-from-pod
kubectl apply -f curl-pod.yaml
kubectl cp direct-access.sh api-curl:/tmp/direct-access.sh
kubectl exec api-curl -- sh /tmp/direct-access.sh
#   { "kind": "APIVersions", "versions": [ "v1" ],
#     "serverAddressByClientCIDRs": [ { "clientCIDR": "0.0.0.0/0", "serverAddress": "192.168.58.2:8443" } ] }
kubectl exec api-curl -- sh -c 'env | grep ^KUBERNETES_SERVICE'
#   KUBERNETES_SERVICE_HOST=10.96.0.1
#   KUBERNETES_SERVICE_PORT=443
#   KUBERNETES_SERVICE_PORT_HTTPS=443
kubectl get endpointslices -l kubernetes.io/service-name=kubernetes      # 192.168.58.2:8443 (the real API server)
```
What each piece protects (not from the docs):
```bash
kubectl exec api-curl -- curl -s https://kubernetes.default.svc/api
#   SSL certificate problem: unable to get local issuer certificate          <- no --cacert
kubectl exec api-curl -- sh -c 'curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt https://kubernetes.default.svc/api | grep message'
#   "message": "forbidden: User \"system:anonymous\" cannot get path \"/api\"",   <- no token
minikube ssh -- sudo openssl x509 -in /var/lib/minikube/certs/apiserver.crt -noout -ext subjectAltName
#   DNS:kubernetes.default.svc, …, IP Address:10.96.0.1, …     <- both names verify here (only the IP is guaranteed)
```

## Lab 2 – Real requests need RBAC (not from the docs)
```bash
Q='S=/var/run/secrets/kubernetes.io/serviceaccount; curl -s --cacert $S/ca.crt -H "Authorization: Bearer $(cat $S/token)" https://kubernetes.default.svc/api/v1/namespaces/$(cat $S/namespace)/pods'
kubectl exec api-curl -- sh -c "$Q" | grep message
#   "message": "pods is forbidden: User \"system:serviceaccount:default:default\" cannot list resource \"pods\" in API group \"\" in the namespace \"default\"",
kubectl apply -f rbac-pod-reader.yaml
kubectl exec api-curl -- sh -c "$Q" | grep -o '"name": "api-curl"' | head -1      # "name": "api-curl"
```
(In real apps, give each app its own ServiceAccount rather than granting rights to `default`.)

## Lab 3 – `kubectl proxy` sidecar (docs, described only)
```bash
kubectl apply -f proxy-sidecar-pod.yaml
kubectl logs api-proxy -c kubectl-proxy        # Starting to serve on 127.0.0.1:8001
kubectl logs api-proxy -c app                  # plain http://localhost:8001, no token, no CA
#   "name": "api-curl"
#   "name": "api-proxy"
#   "name": "api-python"
```
The proxy uses the Pod's ServiceAccount, so the Role from Lab 2 applies here too.

## Lab 4 – Official client library (docs, Python)
```bash
kubectl apply -f python-client.yaml
kubectl logs api-python
#   host: https://10.96.0.1:443                <- from KUBERNETES_SERVICE_HOST/PORT
#   pod: api-curl Running
#   pod: api-proxy Running
#   pod: api-python Running
```
Go is the same idea with `rest.InClusterConfig()`.

## Cleanup
```bash
./cleanup.sh
```
