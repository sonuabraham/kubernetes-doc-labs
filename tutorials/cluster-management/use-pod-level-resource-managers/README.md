# Use Pod-Level Resources with kubelet Resource Managers – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/cluster-management/use-pod-level-resource-managers/

> Needs the `PodLevelResourceManagers` gate (**beta but off by default** in v1.37: `kubernetes_feature_enabled{name="PodLevelResourceManagers",stage="BETA"} 0`)
> and kubelet configuration changes, so it runs on a throwaway profile **`plrm-lab`** made by [setup-node.sh](setup-node.sh) (NOT from the
> docs). The node is the minikube container: 8 host CPUs, **1 NUMA node**. The three Pod manifests are the docs examples **verbatim**.
>
> **Found / notes:**
> - **The docs' four kubelet lines aren't enough on their own.** The static CPU and Memory managers also need reserved resources, or
>   the kubelet doesn't start (e.g. `[memorymanager] you should specify the system reserved memory`). setup-node.sh adds
>   `reservedSystemCPUs: "0"`, `kubeReserved`/`systemReserved` and `reservedMemory` (306Mi, the sum rule from
>   [tasks/…/memory-manager](../../../tasks/administer-cluster/memory-manager/)). It also deletes `cpu_manager_state`/`memory_manager_state`
>   while the kubelet is stopped, which is required when policies change.
> - **Step 5 fails differently if the Step 2 Pod is still running:** `FailedScheduling … 1 Insufficient cpu`. Allocatable is `7` CPUs
>   (8 − 1 reserved), and both Pods want 4. The page never deletes `pod-scope-mixed`. Delete it first on a small node.
> - Step 4's text names the containers `container-a` (1 CPU), `container-b` (3 CPUs), `container-c`. The manifest uses `metrics-sidecar`
>   (1 CPU), `main-app` (3 CPUs) and `logging-sidecar`.
> - The shared-pool sidecars have CFS quota `400000 100000` (the Pod's 4-CPU limit), not 2 CPUs. Their **cpuset** (2 CPUs) is what limits
>   them to the pool's 2 CPUs.
> - With 1 NUMA node, "single NUMA alignment" always succeeds (`numaAffinity: [0]`); there's nothing to mis-align.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Pod-level resources (`spec.resources`) | one CPU/memory budget for the whole Pod; containers without requests share it |
| `topologyManagerScope: pod` | **one** NUMA alignment for the Pod's budget; Guaranteed containers get exclusive slices from it, the rest share the remainder (**pod shared pool**, isolated from other Pods) |
| Empty shared pool | exclusive containers use up the whole budget while another container needs the pool → kubelet rejects (`TopologyAffinityError`) |
| `topologyManagerScope: container` | each container aligned on its own; containers without requests run in the **node** shared pool, capped by the Pod limit |
| Allowed policies | `single-numa-node`, `restricted`, `best-effort` |

## Lab
```bash
cd tutorials/cluster-management/use-pod-level-resource-managers
minikube stop
./setup-node.sh start           # profile plrm-lab, --feature-gates=PodLevelResourceManagers=true
./setup-node.sh scope pod       # Step 1
#   {'cpuManagerPolicy': 'static', 'memoryManagerPolicy': 'Static', 'topologyManagerScope': 'pod',
#    'topologyManagerPolicy': 'single-numa-node', 'featureGates': {'PodLevelResourceManagers': True}}
kubectl create namespace plrm-tutorial
```

### Steps 2–3: pod scope, mixed allocation
```bash
kubectl apply -f pod-level-resource-managers-pod-scope-mixed.yaml --namespace=plrm-tutorial
kubectl get pod pod-scope-mixed --namespace=plrm-tutorial       # 3/3 Running   (QoS Guaranteed)
```
NOT from the docs – see the partition:
```bash
minikube -p plrm-lab ssh -- sudo cat /var/lib/kubelet/cpu_manager_state
#   "defaultCpuSet":"0,5-7"
#   entries: main-app "1-2", metrics-sidecar "3-4", logging-sidecar "3-4"      podEntries: cpuSet "1-4"
#   → the Pod got CPUs 1-4: main-app exclusive 1-2, both sidecars share 3-4 (pod shared pool)
# memory_manager_state: every container numaAffinity [0]
# cgroups (/sys/fs/cgroup/kubepods.slice/kubepods-pod<uid>.slice/…):
#   pod:              cpu.max 400000 100000   memory.max 4294967296
#   main-app:         cpu.max max 100000      cpuset 1-2   memory.max 2147483648     <- no CFS throttling
#   metrics-sidecar:  cpu.max 400000 100000   cpuset 3-4   memory.max 4294967296
#   logging-sidecar:  cpu.max 400000 100000   cpuset 3-4   memory.max 4294967296
```

### Steps 4–5: empty shared pool
```bash
kubectl apply -f pod-level-resource-managers-empty-shared-pool.yaml --namespace=plrm-tutorial
kubectl get pod empty-shared-pool -n plrm-tutorial    # Pending: FailedScheduling … Insufficient cpu   <- pod-scope-mixed still holds 4 CPUs
kubectl delete pod pod-scope-mixed empty-shared-pool -n plrm-tutorial
kubectl apply -f pod-level-resource-managers-empty-shared-pool.yaml --namespace=plrm-tutorial
kubectl describe pod empty-shared-pool --namespace=plrm-tutorial
#   Status:   Failed
#   Reason:   TopologyAffinityError
#   Message:  Pod was rejected: Pod Scope pod with pod-level resources failed admission under pod-scope topology manager
kubectl delete pod empty-shared-pool -n plrm-tutorial
```

### Steps 6–8: container scope
```bash
./setup-node.sh scope container  # Step 6 (state files removed, kubelet restarted)
kubectl apply -f pod-level-resource-managers-container-scope-mixed.yaml --namespace=plrm-tutorial
kubectl get pod container-scope-mixed --namespace=plrm-tutorial   # 3/3 Running
# NOT from the docs:
#   cpu_manager_state: defaultCpuSet "0,3-7", entries: infrastructure-sidecar "1-2"
#   infrastructure-sidecar: cpu.max max 100000   cpuset 1-2     memory.max 2Gi   <- exclusive
#   worker-1 / worker-2:    cpu.max 400000 100000 cpuset 0,3-7  memory.max 4Gi   <- node shared pool, capped by the Pod limit
```

## Cleanup
```bash
./cleanup.sh       # docs: kubectl delete namespace plrm-tutorial; then minikube delete -p plrm-lab; minikube start
```
