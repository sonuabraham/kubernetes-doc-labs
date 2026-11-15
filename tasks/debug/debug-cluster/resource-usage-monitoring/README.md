# Tools for Monitoring Resources – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-usage-monitoring/

> A concept page comparing the **resource metrics pipeline** (metrics-server → `metrics.k8s.io`, see
> [resource-metrics-pipeline](../resource-metrics-pipeline/)) with a **full metrics pipeline**. The page recommends no product,
> so [prometheus.yaml](prometheus.yaml) (not from the docs) is the smallest full pipeline possible: a single Prometheus scraping each
> kubelet's cAdvisor endpoint through the API server proxy. Runs on the default **minikube** cluster, namespace `monitoring-demo`.

## Key ideas (read first)

| | Resource metrics pipeline | Full metrics pipeline |
|---|---|---|
| What | CPU + memory per node/Pod/container, the latest value only | everything the components expose in OpenMetrics/Prometheus format: network, disk, throttling, app metrics… |
| Who | metrics-server (in memory, short-term) | Prometheus and similar (time-series database, history, queries, alerts) |
| API back into Kubernetes | `metrics.k8s.io` (HPA on cpu/memory, VPA, `kubectl top`) | `custom.metrics.k8s.io` / `external.metrics.k8s.io` via an **adapter** (HPA on any metric) |
| Source | kubelet `/metrics/resource` | kubelet `/metrics/cadvisor`, `/metrics`, `/metrics/probes`, component `/metrics`, exporters, apps |

---

## Step 0
```bash
cd tasks/debug/debug-cluster/resource-usage-monitoring
kubectl top pod -A | head -3            # the resource pipeline: two numbers per Pod, now
kubectl apply -f prometheus.yaml
kubectl rollout status deploy/prometheus -n monitoring-demo
q(){ kubectl exec -n monitoring-demo deploy/prometheus -- wget -qO- "http://localhost:9090/api/v1/query?query=$1"; }
```

## Lab 1 – Is it scraping?
```bash
kubectl exec -n monitoring-demo deploy/prometheus -- wget -qO- http://localhost:9090/api/v1/targets \
  | jq -c '.data.activeTargets[]|{job:.labels.job, health, url:.scrapeUrl}'
#   {"job":"kubelet-cadvisor","health":"up","url":"https://kubernetes.default.svc:443/api/v1/nodes/minikube/proxy/metrics/cadvisor"}
```
Node discovery (`kubernetes_sd_configs: role: node`) plus a relabel to the API server proxy path. RBAC needed: `nodes` list/watch and `nodes/proxy` get.

## Lab 2 – What the full pipeline adds
```bash
q 'count({job="kubelet-cadvisor"})'                           # 3245 series from ONE node
q 'count(count by (__name__)({job="kubelet-cadvisor"}))'       # 96 different metric names
q 'topk(3, sum by (namespace,pod)(rate(container_network_receive_bytes_total[1m])))'
#   monitoring-demo/prometheus-…    2304 B/s
#   kube-system/metrics-server-…     450 B/s
#   kube-system/csi-hostpathplugin-… 444 B/s          <- network: not in the Metrics API at all
q 'topk(3, container_cpu_cfs_throttled_periods_total)'
#   kube-system/kindnet-…/kindnet-cni  64             <- CPU throttling: invisible in `kubectl top`
q 'max_over_time(container_memory_working_set_bytes{container="kube-apiserver"}[5m])'
#   274063360                                          <- history: metrics-server only knows "now"
```
(URL-encode the queries for `wget`. In the lab run they were passed as `%7B…%7D` etc.)

## Lab 3 – Getting these metrics back into Kubernetes
```bash
kubectl get apiservices | grep -E 'custom.metrics|external.metrics'     # (nothing)
kubectl get --raw /apis/custom.metrics.k8s.io
#   Error from server (NotFound): the server could not find the requested resource
```
Without an adapter (prometheus-adapter, KEDA, a cloud provider's adapter…), an HPA can only use `cpu`/`memory`.
The adapter registers `custom.metrics.k8s.io` through the aggregation layer, just as metrics-server registers `metrics.k8s.io`.

## Useful commands
```bash
kubectl get --raw /api/v1/nodes/minikube/proxy/metrics/cadvisor | grep -c '^container_'
kubectl port-forward -n monitoring-demo deploy/prometheus 9090      # then http://localhost:9090
```

## Cleanup
```bash
./cleanup.sh
```
