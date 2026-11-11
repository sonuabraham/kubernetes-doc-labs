# Container Runtime Interface (CRI) – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/containers/cri/

> Cluster: default **`minikube`** (containerd 2.x).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **CRI** | The gRPC plugin interface between the **kubelet** (client) and the **container runtime** (server). Any CRI-compliant runtime works without recompiling Kubernetes. |
| **Two services** | **RuntimeService** (pod sandboxes, containers, exec/attach/port-forward…) and **ImageService** (pull/list/remove images). |
| **Endpoint** | The kubelet's `--container-runtime-endpoint` / `containerRuntimeEndpoint`, here `unix:///run/containerd/containerd.sock`. |
| **API version** | Stable since 1.23. Since **v1.26 the kubelet requires CRI `v1`**, and a runtime without it can't register the node. |
| **Upgrades** | The kubelet re-dials the runtime over gRPC after it restarts. The runtime must speak v1. |
| **List streaming** | `CRIListStreaming` (alpha): streaming List RPCs for nodes with ~10k+ containers, where unary responses exceed gRPC's 16 MiB limit. Falls back to unary automatically. |
| **crictl** | A CRI client for humans. It sends the same calls the kubelet sends. |

## The demo app
[crictl-direct.sh](crictl-direct.sh) uses [sandbox.json](sandbox.json) and [container.json](container.json) to run `RunPodSandbox → CreateContainer → StartContainer` by hand, so you get a container **without** a Pod.

---

## Lab 1 – The kubelet ↔ runtime connection
```bash
minikube ssh -- "sudo grep containerRuntimeEndpoint /var/lib/kubelet/config.yaml"
#   containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
minikube ssh -- sudo crictl version
#   RuntimeName:  containerd   RuntimeVersion:  v2.3.4   RuntimeApiVersion:  v1     <- the v1 CRI the kubelet requires
kubectl get node minikube -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}{"\n"}'     # containerd://2.3.4
minikube ssh -- "sudo crictl info | grep -A3 runtimeHandlers"        # handlers RuntimeClass can use (see ../runtime-class)
```

## Lab 2 – What the kubelet asks the runtime
```bash
kubectl get --raw /api/v1/nodes/minikube/proxy/metrics | grep '^kubelet_runtime_operations_total' | sort -t' ' -k2 -nr | head
#   kubelet_runtime_operations_total{operation_type="list_containers"} 74570
#   kubelet_runtime_operations_total{operation_type="list_podsandbox"} 73763      <- constant reconciliation via List RPCs
#   kubelet_runtime_operations_total{operation_type="status"} 9992
#   ... create_container, start_container, pull_image, exec_sync ...
kubectl get --raw /api/v1/nodes/minikube/proxy/metrics | grep '^kubelet_runtime_operations_errors_total'
```
Those huge `list_*` counts are why `CRIListStreaming` exists for very busy nodes:
```bash
kubectl get --raw /api/v1/nodes/minikube/proxy/metrics | grep 'feature_enabled{name="CRIListStreaming"'
#   kubernetes_feature_enabled{name="CRIListStreaming",stage="ALPHA"} 0
```

## Lab 3 – Speak CRI yourself (a container Kubernetes doesn't know)
```bash
cd concepts/containers/cri
./crictl-direct.sh start
#   sandbox: 6fabd2439aa4…          <- RunPodSandbox (the pause container + network namespace)
#   container: ae1f526be660…        <- CreateContainer + StartContainer
#   ae1f526be6604  busybox:1.36  Running  sleeper  …  POD unknown  NAMESPACE unknown
kubectl get pods -A | grep -c made-by-crictl                       # 0 - no Pod object anywhere
kubectl describe node minikube | grep -c made-by-crictl            # 0 - not counted in "Allocated resources"
./crictl-direct.sh stop
```
This is the docs' (Nodes page) point that the scheduler's accounting **excludes containers started directly by the runtime**. Note `cgroup_parent: system.slice` in `sandbox.json`: with the **systemd cgroup driver**, a plain path is rejected (`expected cgroupsPath to be of format "slice:prefix:name"`).

## Lab 4 – Runtime restart, kubelet re-dials
```bash
minikube ssh -- sudo systemctl restart containerd
kubectl get node minikube                    # stays Ready
kubectl get pods -A | grep -c Running        # workloads untouched - containers are owned by containerd-shim processes
```

---

## Useful commands
```bash
minikube ssh -- sudo crictl pods | ps -a | images | inspect <id> | inspectp <pod-id> | logs <id> | stats
minikube ssh -- sudo crictl info              # runtime config, CNI, handlers
kubectl get --raw /api/v1/nodes/<node>/proxy/metrics | grep kubelet_runtime_operations
```
Protocol definition: https://github.com/kubernetes/cri-api/blob/master/pkg/apis/runtime/v1/api.proto

## Cleanup
```bash
./crictl-direct.sh stop      # if still running
```
