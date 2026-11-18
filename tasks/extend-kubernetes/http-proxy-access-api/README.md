# Use an HTTP Proxy to Access the Kubernetes API – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/extend-kubernetes/http-proxy-access-api/

> Runs on the default **minikube** cluster. The page's commands only, run as written; the extras show what the proxy also allows.
> More on `kubectl proxy` (IPv6, `--accept-hosts`, tokens instead of a proxy): [access-cluster](../../access-application-cluster/access-cluster/).
>
> **Note:** the proxy holds your kubeconfig credentials (here cluster-admin). Anything that can reach `127.0.0.1:8080` can **write** to the
> cluster with your identity, deletes included (Lab 2). Keep it on localhost and stop it when you're done.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `kubectl proxy --port=8080` | plain HTTP on `127.0.0.1:8080` → HTTPS to the API server with your credentials |
| What you can call | the whole REST API: discovery, lists, watches, writes, and the API server's own proxy to Pods/Services |
| Protection | listens on localhost; `--accept-hosts` (default localhost/127.0.0.1) rejects other `Host` headers with `Forbidden` |

---

## Lab 1 – The docs' steps
```bash
cd tasks/extend-kubernetes/http-proxy-access-api
kubectl create deployment hello-app --image=gcr.io/google-samples/hello-app:2.0 --port=8080
kubectl proxy --port=8080 &              # Starting to serve on 127.0.0.1:8080
curl http://localhost:8080/api/
#   {"kind":"APIVersions","versions":["v1"],"serverAddressByClientCIDRs":[{"clientCIDR":"0.0.0.0/0","serverAddress":"192.168.58.2:8443"}]}
curl http://localhost:8080/api/v1/namespaces/default/pods | jq -r '.kind, (.items[] | .metadata.name + "  " + (.metadata.labels|tostring))'
#   PodList
#   hello-app-6974d446d6-t25z8  {"app":"hello-app","pod-template-hash":"6974d446d6"}
```

## Lab 2 – More through the same proxy (not from the docs)
```bash
P=$(kubectl get pod -l app=hello-app -o jsonpath='{.items[0].metadata.name}')
curl http://localhost:8080/api/v1/namespaces/default/pods/$P:8080/proxy/        # the app via the API server's pod proxy
#   Hello, world!  Version: 2.0.0  Hostname: hello-app-6974d446d6-t25z8
timeout 3 curl -sN "http://localhost:8080/api/v1/namespaces/default/pods?watch=true&labelSelector=app=hello-app" | jq -r '.type + " " + .object.metadata.name'
#   ADDED hello-app-6974d446d6-t25z8                  <- watches stream through it
curl -s -X DELETE http://localhost:8080/api/v1/namespaces/default/pods/$P | jq -r .metadata.deletionTimestamp
#   2026-11-18T11:19:38Z                              <- and writes, with your (admin) rights
curl -H 'Host: evil.example' http://localhost:8080/api/
#   Forbidden                                         <- --accept-hosts check (DNS-rebinding protection)
kill %1
```

## Cleanup
```bash
./cleanup.sh
```
