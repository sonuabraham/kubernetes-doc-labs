# Metrics For Kubernetes System Components – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/system-metrics/

> The docs' ClusterRole is **verbatim** in [clusterrole-prometheus.yaml](clusterrole-prometheus.yaml), and the `--allow-metric-labels-manifest` example in [allow-metric-labels-manifest-excerpt.yaml](allow-metric-labels-manifest-excerpt.yaml). [00-scraper.yaml](00-scraper.yaml) binds the role to a ServiceAccount `prometheus`. The lab then scrapes every component like Prometheus would, from inside the node, since the components listen on 127.0.0.1.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Endpoints** | Every component serves Prometheus text on `/metrics` (HTTPS, authn + authz): API server, controller-manager `:10257`, scheduler `:10259`, kubelet `:10250` (+ `/metrics/cadvisor`, `/metrics/resource`, `/metrics/probes`), kube-proxy. |
| **Stability** | `ALPHA` (may change anytime), `BETA`, `STABLE` (no breaking changes), shown in the `# HELP` line. Deprecated metrics get hidden, then removed. `--show-hidden-metrics-for-version=<previous minor>` brings them back for one release. |
| **Scheduler resources** | `/metrics/resources`: `kube_pod_resource_request` / `_limit`, i.e. what the scheduler thinks every Pod requests. |
| **PSI** (KubeletPSI, GA here) | Pressure Stall Information per container/Pod/node: `container_pressure_{cpu,memory,io}_{waiting,stalled}_seconds_total`, from `/proc/pressure`. |
| **Disabling / cardinality** | `--disabled-metrics`, `--allow-metric-labels` (or `--allow-metric-labels-manifest`) to cap label values. |

---

## Lab 1 – Scrape with the docs' ClusterRole
```bash
cd concepts/cluster-administration/system-metrics
kubectl apply -f clusterrole-prometheus.yaml -f 00-scraper.yaml
T=$(kubectl create token prometheus -n metrics-lab)
minikube ssh -- "curl -sk -H 'Authorization: Bearer $T' https://127.0.0.1:10257/metrics | grep -c '^# HELP'"
```
| Component | Metrics | STABLE | BETA | ALPHA |
|---|---|---|---|---|
| API server `:8443` | 323 | 10 | 33 | 127 |
| controller-manager `:10257` | 259 | 6 | 27 | 77 |
| scheduler `:10259` | 232 | 8 | 22 | 53 |
| **kubelet `:10250`** | **0** (HTTP 403) | | | |

## Lab 2 – What the docs' role is missing
The kubelet doesn't authorize `/metrics` as a non-resource URL. It asks for **`nodes/metrics`** (a node subresource), and the scheduler's `/metrics/resources` is a different path:
```bash
kubectl apply -f 01-clusterrole-extra.yaml        # nonResourceURLs /metrics/resources, /metrics/slis + nodes/metrics
minikube ssh -- "curl -sk -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer $T' https://127.0.0.1:10250/metrics"
#   still 403 for up to 30s - the kubelet caches DENY decisions (authorization.webhook.cacheUnauthorizedTTL: 30s; allow: 5m)
#   then 200: kubelet: 292 metrics  STABLE=0 BETA=21 ALPHA=121
minikube ssh -- "curl -sk -H 'Authorization: Bearer $T' https://127.0.0.1:10259/metrics/resources | grep ^kube_pod_resource_request | head -2"
#   kube_pod_resource_request{namespace="kube-system",node="minikube",pod="coredns-…",priority="2000000000",resource="cpu",scheduler="default-scheduler",unit="cores"} 0.1
```

## Lab 3 – PSI metrics
```bash
minikube ssh -- "curl -sk -H 'Authorization: Bearer $T' https://127.0.0.1:10250/metrics/cadvisor | grep ^container_pressure_cpu_waiting | head -2; cat /proc/pressure/cpu"
#   container_pressure_cpu_waiting_seconds_total{id="/",...} 428.83
#   container_pressure_cpu_waiting_seconds_total{id="/kubepods.slice",...} 375.82
#   some avg10=0.48 avg60=1.27 avg300=0.90 total=1275693971
#   full avg10=0.00 avg60=0.00 avg300=0.00 total=0
```
`some` > 0 and `full` = 0: some tasks waited for CPU, but never everything at once, which is the docs' example interpretation.

---

## Useful commands
```bash
kubectl get --raw /metrics | grep '^# HELP' | grep -c STABLE
kubectl get --raw /api/v1/nodes/<n>/proxy/metrics/cadvisor | grep container_pressure    # via the API server (admin)
```

## Cleanup
```bash
./cleanup.sh
```
