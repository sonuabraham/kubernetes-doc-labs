# Access Services Running on Clusters – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/access-application-cluster/access-cluster-services/

> Runs on the default **minikube** cluster. The page has no manifests; its examples (Elasticsearch, Kibana, Grafana, Heapster) don't exist
> on a modern cluster. This lab uses, **not from the docs**: [web-service.yaml](web-service.yaml) (nginx behind a Service with two
> **named** ports `http`/`alt`), [web-unnamed-port.yaml](web-unnamed-port.yaml) (one unnamed port), and minikube's own `metrics-server` (HTTPS) and `kube-dns`.
>
> **Found:**
> 1. The short forms `<service>` and `https:<service>:` (empty port) only work when the Service has a **single unnamed** port. With a named
>    port, even a single one (metrics-server's `https`), you get `no endpoints available for service …`, which is misleading.
>    Give the port name (or number): `https:metrics-server:https`.
> 2. `kubectl cluster-info` lists `CoreDNS is running at …/services/kube-dns:dns/proxy`, but that is the **DNS** port. Opening it gives
>    `error trying to reach service: EOF`; only `kube-dns:metrics` is HTTP.

## Key ideas (read first)

| URL part | Meaning |
|---|---|
| `/api/v1/namespaces/<ns>/services/<svc>/proxy/<path>` | API server proxies HTTP to the Service (picks an endpoint) |
| `<svc>:<port-name-or-number>` | choose the Service port |
| `https:<svc>:<port>` | API server talks **TLS** to the backend (no verification of its cert) |
| `pods/<pod>:<port>/proxy`, `nodes/<node>/proxy` | same for a Pod or the kubelet |
| RBAC | `get` on `services/proxy` (or `pods/proxy`, `nodes/proxy`), authenticated by the API server first |

---

## Lab 1 – Built-in services (docs)
```bash
cd tasks/access-application-cluster/access-cluster-services
kubectl cluster-info
#   Kubernetes control plane is running at https://192.168.58.2:8443
#   CoreDNS is running at https://192.168.58.2:8443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
kubectl get --raw /api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
#   Error from server (ServiceUnavailable): error trying to reach service: EOF     <- port 53 isn't HTTP
kubectl get --raw /api/v1/namespaces/kube-system/services/kube-dns:metrics/proxy/metrics | grep -m1 coredns_build_info
#   coredns_build_info{goversion="go1.26.5",revision="424d125",version="1.14.6"} 1
```

## Lab 2 – Constructing proxy URLs (docs formats, tested)
```bash
kubectl apply -f web-service.yaml -f web-unnamed-port.yaml
A=/api/v1/namespaces/default/services
kubectl get --raw "$A/web-unnamed/proxy/"   | grep -o '<title>.*</title>'   # <title>Welcome to nginx!</title>   (unnamed port)
kubectl get --raw "$A/web/proxy/"                                            # no endpoints available for service "web"   (named ports)
kubectl get --raw "$A/web:http/proxy/"      | grep -o '<title>.*</title>'   # Welcome to nginx!   (port name)
kubectl get --raw "$A/web:8080/proxy/"      | grep -o '<title>.*</title>'   # Welcome to nginx!   (port number)
kubectl get --raw "$A/https:web:http/proxy/"
#   error trying to reach service: tls: first record does not look like a TLS handshake    <- https: to a plain-HTTP port
kubectl get --raw "/api/v1/namespaces/kube-system/services/https:metrics-server:/proxy/healthz"
#   no endpoints available for service "metrics-server"      <- docs' "https:<service_name>:" form; the port is named "https"
kubectl get --raw "/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy/readyz"      # ok
P=$(kubectl get pod -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl get --raw "/api/v1/namespaces/default/pods/$P:80/proxy/" | grep -o '<title>.*</title>'          # Pod proxy
kubectl get --raw /api/v1/nodes/minikube/proxy/healthz                                                  # ok   (kubelet)
```

## Lab 3 – Through `kubectl proxy`, and RBAC (docs)
```bash
kubectl proxy --port=8080 &
curl -s http://localhost:8080/api/v1/namespaces/default/services/web:http/proxy/ | grep -o '<title>.*</title>'
#   <title>Welcome to nginx!</title>        <- also works in a browser (http://localhost:8080/…)
kill %1
TOKEN=$(kubectl create token default --duration=10m)
curl -s --cacert ~/.minikube/ca.crt -H "Authorization: Bearer $TOKEN" \
  https://$(minikube ip):8443/api/v1/namespaces/default/services/web:http/proxy/ | jq -r .message
#   services "web:http" is forbidden: User "system:serviceaccount:default:default" cannot get resource "services/proxy" …
```
The page's warning about web apps applies: pages with absolute links (`href="/…"`) break under the `/api/v1/…/proxy/` prefix.

## Cleanup
```bash
./cleanup.sh
```
