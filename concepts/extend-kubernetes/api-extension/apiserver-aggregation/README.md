# Kubernetes API Aggregation Layer – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/apiserver-aggregation/

> The page has no YAML. The lab builds a **real extension API server** you can read in a few minutes:
>
> | File | What |
> |---|---|
> | [toy_apiserver.py](toy_apiserver.py) | Python stdlib, HTTPS. Serves group `toys.example.com/v1` with discovery and two **computed** resources: `clocks` (cluster-scoped) and `whoamis` (namespaced, returns the caller's identity). Nothing is stored in etcd. Trusts `X-Remote-User`/`X-Remote-Group` **only** from a client cert signed by the front-proxy CA with CN `front-proxy-client`. |
> | [00-toy-apiserver.yaml](00-toy-apiserver.yaml) | Deployment (python:3.12-slim, code from a ConfigMap) + Service in `agg-demo` |
> | [01-apiservice.yaml](01-apiservice.yaml) | APIService `v1.toys.example.com` → the Service, with `caBundle` |
> | [deploy.sh](deploy.sh) | Creates a CA + serving cert, copies the cluster's requestheader CA, deploys, and fills in `caBundle` |
> | [02-rbac-devs.yaml](02-rbac-devs.yaml) | RBAC on the aggregated resources for group `devs` |
> | [03-spoof.yaml](03-spoof.yaml) | Calls the server directly with forged identity headers |

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Aggregation layer** | Runs **inside kube-apiserver**. Does nothing until an **APIService** claims a path (`/apis/<group>/<version>`), then **proxies** those requests to the registered backend. |
| **Extension API server** | Your own API server, usually Pods + Service, often paired with controllers. Examples: **metrics-server** (`metrics.k8s.io`), custom metrics adapters. |
| **APIService** | `group`, `version`, `service` (namespace/name/port), `caBundle` (to verify the backend's cert), `groupPriorityMinimum`/`versionPriority` (discovery order). Built-in groups are APIServices with `SERVICE: Local`. |
| **Request flow** | client → kube-apiserver **authenticates and authorizes** (RBAC on the aggregated resource) → proxies over TLS with the **front-proxy client cert**, adding `X-Remote-User`/`X-Remote-Group`/`X-Remote-Extra-*` → extension server. |
| **Trusting the headers** | The extension must check the client cert against the **requestheader CA** and allowed names (published in `kube-system/extension-apiserver-authentication`). Otherwise anyone who reaches the Pod can claim to be admin. |
| **vs. CRDs** | Aggregation gives full control (custom storage, computed resources, protobuf, extra subresources), at the cost of a service you must run, secure and keep available (see `../custom-resources`). |
| **Latency** | Discovery must round-trip in **≤ 5s**. Slow or dead backends make the APIService `Available=False`, and their resources fail. |

---

## Lab 1 – The APIServices already there
```bash
cd concepts/extend-kubernetes/api-extension/apiserver-aggregation
kubectl get apiservices | grep -v Local
#   v1beta1.metrics.k8s.io   kube-system/metrics-server   True     <- metrics-server is an aggregated API
kubectl get apiservices | grep -c Local                               # 24   <- built-in groups, served in-process
kubectl get cm extension-apiserver-authentication -n kube-system -o jsonpath='{.data.requestheader-allowed-names} {.data.requestheader-username-headers} {.data.requestheader-group-headers}'
#   ["front-proxy-client"] ["X-Remote-User"] ["X-Remote-Group"]
```

## Lab 2 – Register your own API
```bash
./deploy.sh
kubectl get apiservice v1.toys.example.com
#   NAME                  SERVICE                  AVAILABLE
#   v1.toys.example.com   agg-demo/toy-apiserver   True
kubectl api-resources --api-group=toys.example.com
#   clocks    clk   toys.example.com/v1   false   Clock
#   whoamis         toys.example.com/v1   true    WhoAmI
kubectl get clocks                          # utc sydney london new-york kolkata   (AGE <unknown>: no creationTimestamp)
kubectl get clk sydney -o jsonpath='{.time}'          # 2026-11-12 20:20:31   - computed per request
kubectl logs deploy/toy-apiserver -n agg-demo
#   GET /apis/toys.example.com/v1  tls-client-cn=front-proxy-client  X-Remote-User=system:kube-aggregator   <- discovery
#   GET /apis/toys.example.com/v1/clocks  tls-client-cn=front-proxy-client  X-Remote-User=minikube-user
```
kubectl doesn't know or care that `clocks` comes from another server.

## Lab 3 – Authentication and authorization happen in kube-apiserver
```bash
kubectl get whoamis -n default -o jsonpath='{.items[0].user} {.items[0].groups} via={.items[0].via}'
#   minikube-user ["system:masters","system:authenticated"] via=front-proxy-client
kubectl get --raw /apis/toys.example.com/v1/namespaces/default/whoamis/me --as=jane --as-group=devs
#   Forbidden: User "jane" cannot get resource "whoamis" in API group "toys.example.com"    <- never reached the backend
kubectl apply -f 02-rbac-devs.yaml
kubectl get --raw /apis/toys.example.com/v1/namespaces/default/whoamis/me --as=jane --as-group=devs
#   {"kind": "WhoAmI", ..., "user": "jane", "groups": ["devs", "system:authenticated"], "via": "front-proxy-client"}
```

## Lab 4 – Why the extension must verify the proxy
```bash
kubectl apply -f 03-spoof.yaml              # curl straight to the Service: X-Remote-User: admin, X-Remote-Group: system:masters
kubectl logs spoof -n agg-demo
#   {"kind": "WhoAmI", ..., "user": "system:anonymous", "groups": [], "via": "no client certificate"}
kubectl logs deploy/toy-apiserver -n agg-demo | tail -1
#   GET .../whoamis/me  tls-client-cn=None  X-Remote-User=admin  -> treated as system:anonymous
```
Without the client-cert check, that request would have been "admin". Real extension servers built with `k8s.io/apiserver` do this check (and delegated authn/authz) for you. Add a NetworkPolicy that only admits the control plane, as a second layer.

## Lab 5 – A new point of failure
Backend gone:
```bash
kubectl scale deploy toy-apiserver -n agg-demo --replicas=0
kubectl get apiservice v1.toys.example.com -o jsonpath='{.status.conditions[0].reason}: {.status.conditions[0].message}'
#   MissingEndpoints: endpointslices for service/toy-apiserver in "agg-demo" have no addresses with port name ""
kubectl get clocks
#   Error from server (ServiceUnavailable): the server is currently unable to handle the request (get clocks.toys.example.com)
kubectl scale deploy toy-apiserver -n agg-demo --replicas=1
```
Backend slower than the 5s discovery budget:
```bash
P=$(kubectl get pod -n agg-demo -l app=toy-apiserver -o name)
kubectl exec -n agg-demo $P -- sh -c 'echo 6 > /tmp/delay'          # every request now sleeps 6s
time kubectl get clocks                                               # still works, but takes 6s
kubectl get apiservice v1.toys.example.com -o jsonpath='{.status.conditions[0].reason}: {.status.conditions[0].message}'
#   (after ~14s) FailedDiscoveryCheck: failing or missing response from https://10.104.195.209:443/apis/toys.example.com/v1:
#   ... context deadline exceeded (Client.Timeout exceeded while awaiting headers)
kubectl exec -n agg-demo $P -- rm /tmp/delay                          # Available=True again on the next check
```
A broken aggregated API also breaks anything that needs **full discovery**, such as namespace deletion (the namespace controller must list every namespaced type) and garbage collection.

---

## Useful commands
```bash
kubectl get apiservices ; kubectl get apiservice <v.group> -o yaml
kubectl get --raw /apis/<group>/<version>
kubectl get cm extension-apiserver-authentication -n kube-system -o yaml
```

## Cleanup
```bash
./cleanup.sh        # APIService first (so discovery doesn't break), then RBAC and the namespace
```
