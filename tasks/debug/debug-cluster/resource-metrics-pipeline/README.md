# Resource metrics pipeline – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/

> Runs on the default **minikube** cluster with the `metrics-server` addon (v0.9.0) enabled.
> Not from the docs: [working-set-demo.yaml](working-set-demo.yaml).
>
> **Found on 1.37 + minikube:** the page marks the Metrics API **stable** and uses `metrics.k8s.io/v1`, but minikube's
> metrics-server v0.9.0 only registers **`v1beta1`**, so the docs' requests return **NotFound**. Everything works with `v1beta1`.

## The pipeline, layer by layer

```
container runtime ─► cAdvisor (in the kubelet) ─► kubelet /metrics/resource, /stats/summary
        ─► metrics-server (scrapes every --metric-resolution=60s) ─► APIService v1beta1.metrics.k8s.io
        ─► kube-apiserver (aggregation layer) ─► kubectl top / HPA / VPA
```

| Topic | Meaning |
|---|---|
| **CPU** | A *rate* over the kernel's cumulative CPU counter, averaged over `window`. `229048598n` = 0.229 cores. |
| **Memory** | **Working set** at the scrape instant = cgroup `memory.current` − `inactive_file`. Active page cache counts, inactive cache doesn't. |
| **Only CPU + memory** | For anything else use a full metrics pipeline ([resource-usage-monitoring](../resource-usage-monitoring/)). |

---

## Step 0 – Is the Metrics API there?
```bash
cd tasks/debug/debug-cluster/resource-metrics-pipeline
kubectl get apiservices | grep metrics           # v1beta1.metrics.k8s.io   kube-system/metrics-server   True
kubectl get --raw /apis/metrics.k8s.io | jq -c '[.versions[].version]'       # ["v1beta1"]
kubectl get deploy metrics-server -n kube-system -o jsonpath='{.spec.template.spec.containers[0].args}'
#   ["--cert-dir=/tmp","--secure-port=4443","--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
#    "--kubelet-use-node-status-port","--metric-resolution=60s","--kubelet-insecure-tls"]
```

## Lab 1 – The docs' Metrics API requests
```bash
kubectl get --raw "/apis/metrics.k8s.io/v1/nodes/minikube"
#   Error from server (NotFound): the server could not find the requested resource        <- docs' version
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes/minikube" | jq -c '{kind,apiVersion,window,usage}'
#   {"kind":"NodeMetrics","apiVersion":"metrics.k8s.io/v1beta1","window":"1m0.249s","usage":{"cpu":"229048598n","memory":"915052Ki"}}
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/namespaces/kube-system/pods/kube-scheduler-minikube" | jq -c '{kind,window,containers}'
#   {"kind":"PodMetrics","window":"1m1.046s","containers":[{"name":"kube-scheduler","usage":{"cpu":"10616682n","memory":"27316Ki"}}]}
kubectl proxy --port=8080 &           # the docs' curl http://localhost:8080/… needs a proxy
curl -s http://localhost:8080/apis/metrics.k8s.io/v1beta1/nodes/minikube | jq -c .usage      # {"cpu":"229048598n","memory":"915052Ki"}
kill %1
```
The `window` is 60 s, not the docs' 30 s, because minikube runs metrics-server with `--metric-resolution=60s`.

## Lab 2 – One level down: the kubelet
```bash
kubectl get --raw /api/v1/nodes/minikube/proxy/metrics/resource | grep -E '^(node_cpu_usage_seconds_total|node_memory_working_set_bytes)'
#   node_cpu_usage_seconds_total 673.751329 …          <- the cumulative counter metrics-server turns into a rate
#   node_memory_working_set_bytes 9.2491776e+08 …      <- 903240Ki now; the Metrics API showed 915052Ki from its last (60 s) scrape
kubectl get --raw /api/v1/nodes/minikube/proxy/stats/summary | jq -c '{cpu_nano:.node.cpu.usageNanoCores, ws:.node.memory.workingSetBytes}'
#   {"cpu_nano":223347970,"ws":924917760}               <- the older Summary API, same numbers
kubectl top node                       # minikube  230m  2%  893Mi  2%
kubectl top pod -n kube-system --sort-by=memory | head -4
```

## Lab 3 – What "working set" really is (not from the docs)
```bash
kubectl apply -f working-set-demo.yaml      # writes a 200 MB file -> page cache, then idles
U=$(kubectl get pod ws-demo -o jsonpath='{.metadata.uid}' | tr - _)
C=$(kubectl get pod ws-demo -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's|containerd://||')
minikube ssh -- "d=/sys/fs/cgroup/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-pod$U.slice/cri-containerd-$C.scope
  cur=\$(cat \$d/memory.current); inact=\$(awk '/^inactive_file/{print \$2}' \$d/memory.stat)
  echo current=\$cur inactive_file=\$inact working_set=\$((cur-inact))"
#   current=215846912 inactive_file=209719296 working_set=6127616
kubectl get --raw /api/v1/nodes/minikube/proxy/metrics/resource | grep 'container_memory_working_set_bytes{container="c",namespace="default",pod="ws-demo"}'
#   … 6.127616e+06                  <- exactly the cgroup formula
kubectl top pod ws-demo             # ws-demo  3m  5Mi    <- not 206 MB
```
The cgroup is charged 206 MB, but almost all of it is reclaimable cache, so the working set is about 6 MB. Re-reading the file twice did
**not** move it to `active_file` here. This kernel uses the multi-generational LRU (`/sys/kernel/mm/lru_gen/enabled` = `0x0007`),
which keeps such pages in the "inactive" counters. On classic-LRU kernels, frequently read cache moves to `active_file` and *does* count.

## Useful commands
```bash
kubectl top node; kubectl top pod -A --containers
kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods | jq '.items | length'
kubectl get --raw /api/v1/nodes/<node>/proxy/metrics/resource
kubectl logs -n kube-system deploy/metrics-server
```

## Cleanup
```bash
./cleanup.sh
```
