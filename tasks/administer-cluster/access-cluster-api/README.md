# Access Clusters Using the Kubernetes API – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/access-cluster-api/

> This runs every access path on the page against the default **minikube** cluster:
> - `kubectl config view`
> - `kubectl proxy`
> - a ServiceAccount token with curl: [token-access.sh](token-access.sh) is the docs' commands verbatim, plus a `--cacert` and RBAC check
> - the **Go**, **Python** and **JavaScript** client examples, saved verbatim in [clients/](clients/)
>
> The host has no Go, Node or Python venv, so each client runs in a throwaway `golang`/`python`/`node` container with a flattened kubeconfig. The Java, dotnet and Haskell examples need large toolchains. They work the same way (load the kubeconfig, list Pods) and aren't run here.

## Key ideas (read first)

| Way in | Who finds the server / authenticates | Notes |
|---|---|---|
| **kubectl** | kubeconfig (`server`, CA, user credentials) | `kubectl config view` shows what it knows. Secrets are redacted unless you pass `--raw`. |
| **kubectl proxy** (recommended for raw REST) | kubectl. Clients speak plain HTTP to `localhost:8080`. | It verifies the API server with the kubeconfig CA, so no MITM is possible. Bind it to localhost only. |
| **Bearer token + curl** | You do: `$APISERVER` + `Authorization: Bearer $TOKEN` | `--insecure` skips server verification (MITM risk). Use `--cacert` instead. The token only has its ServiceAccount's RBAC. |
| **Client libraries** | Read the same kubeconfig (`load_kube_config`, `clientcmd`, `loadFromDefault`) | In-cluster they use the mounted ServiceAccount token instead (see Accessing the API from a Pod). |

---

## Step 0
```bash
cd tasks/administer-cluster/access-cluster-api
mkdir -p work && kubectl config view --minify --flatten --context minikube > work/kubeconfig     # for the containers (contains the admin key! gitignored)
```

## Lab 1 – What kubectl knows
```bash
kubectl config view
#   clusters:
#   - cluster:
#       certificate-authority: /home/sonu/.minikube/ca.crt
#       server: https://192.168.58.2:8443
#     name: minikube
#   ...  users: - name: minikube  user: client-certificate: .../client.crt  client-key: .../client.key
```

## Lab 2 – kubectl proxy
```bash
kubectl proxy --port=8080 &
curl http://localhost:8080/api/
#   { "kind": "APIVersions", "versions": [ "v1" ],
#     "serverAddressByClientCIDRs": [ { "clientCIDR": "0.0.0.0/0", "serverAddress": "192.168.58.2:8443" } ] }
curl -s http://localhost:8080/api/v1/namespaces/kube-system/pods | grep -c '"name": "coredns'     # full admin rights via the proxy
kill %1
```

## Lab 3 – Without the proxy: a ServiceAccount token
```bash
./token-access.sh
#   Cluster name	Server
#   minikube	https://192.168.58.2:8443
#   multinode-cluster	https://192.168.49.2:8443
#   secret/default-token created
#   { "kind": "APIVersions", "versions": [ "v1" ], ... "serverAddress": "192.168.58.2:8443" ... }    <- the docs' --insecure call
#   --- with --cacert /home/sonu/.minikube/ca.crt:
#   { "major": "1", "minor": "37", ...                                       <- same call, server verified
#   --- list pods as this ServiceAccount:
#     "message": "pods is forbidden: User \"system:serviceaccount:default:default\" cannot list resource \"pods\" ...",
#     "reason": "Forbidden",                                                 <- authenticated, but no RBAC
#   --- token claims:
#     "iss": "kubernetes/serviceaccount",   "sub": "system:serviceaccount:default:default"   <- a legacy, non-expiring Secret token
```
For short-lived tokens, prefer `kubectl create token default` over Secret-based tokens.

## Lab 4 – Client libraries
**Python** ([clients/python/out_of_cluster.py](clients/python/out_of_cluster.py), `pip install kubernetes`):
```bash
docker run --rm --network host -v $PWD/work/kubeconfig:/root/.kube/config:ro -v $PWD/clients/python:/app:ro python:3.13-slim \
  sh -c 'pip install -q kubernetes; python /app/out_of_cluster.py | head -4'
#   Listing pods with their IPs:
#   10.244.0.2	kube-system	coredns-559f6c778d-fsjkx
#   10.244.0.6	kube-system	csi-hostpath-attacher-0  ...                          (kubernetes 37.0.2)
```
**Go** ([clients/go/main.go](clients/go/main.go)). `go get k8s.io/client-go@kubernetes-1.37.0` resolves to module version `v0.37.0`, which needs Go ≥ 1.26 (`GOTOOLCHAIN=auto` fetches it):
```bash
docker run --rm --network host -e GOTOOLCHAIN=auto -v $PWD/work/kubeconfig:/root/.kube/config:ro -v $PWD/clients/go:/src:ro golang:1.25 \
  sh -c 'mkdir /app && cd /app && sed "s|<path-to-kubeconfig>|/root/.kube/config|" /src/main.go > main.go &&
         go mod init example.com/listpods && go get k8s.io/client-go@v0.37.0 k8s.io/apimachinery@v0.37.0 && go mod tidy && go run .'
#   There are 14 pods in the cluster
```
**JavaScript** ([clients/javascript/example.js](clients/javascript/example.js), `npm install @kubernetes/client-node`):
```bash
docker run --rm --network host -v $PWD/work/kubeconfig:/root/.kube/config:ro -v $PWD/clients/javascript:/src:ro node:22-slim \
  sh -c 'mkdir /app && cd /app && cp /src/example.js . && npm install -s @kubernetes/client-node && node example.js'
#   V1PodList { apiVersion: 'v1', items: [], kind: 'PodList', metadata: V1ListMeta { resourceVersion: '151451' } }   <- "default" ns is empty
```
Note that all three ignore errors and print whatever comes back. In the Go example an auth failure would surface as a nil-pointer panic (`config, _ :=`), so check errors in real code.

---

## Useful commands
```bash
kubectl config view --minify --raw
kubectl proxy --port=8080 --address=127.0.0.1
kubectl get --raw /api/v1/namespaces/default/pods        # REST through kubectl's own auth
kubectl create token default --duration=10m
```

## Cleanup
```bash
./cleanup.sh      # Secret default-token + work/ (the flattened admin kubeconfig)
```
