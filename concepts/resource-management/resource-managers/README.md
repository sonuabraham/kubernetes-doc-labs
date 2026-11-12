# Resource Management for Nodes (Resource Managers) – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/resource-management/resource-managers/

> The docs' six CPU-manager examples (`spec:` fragments) are **verbatim** as `0N-*-excerpt.yaml`. [make-pods.sh](make-pods.sh) wraps each into a Pod named after it. The managers are **kubelet** settings, so the lab runs on a fresh profile **`rm-lab`** ([start-rm-lab.sh](start-rm-lab.sh)): CPU manager `static` (CPU 0 reserved), memory manager `Static`, topology manager `best-effort`.

## Key ideas (read first)

| Manager | Job | Policies |
|---|---|---|
| **CPU manager** | Gives **Guaranteed Pods with integer CPU requests** **exclusive** CPUs (cpuset). Everyone else shares the rest (the shared pool). | `none` (default: CFS quota only), `static` (+ options: `full-pcpus-only`, `distribute-cpus-across-numa`, `align-by-socket`, `distribute-cpus-across-cores`, `strict-cpu-reservation`, `prefer-align-cpus-by-uncorecache`) |
| **Memory manager** | Guarantees memory (and hugepages) from specific **NUMA nodes** for Guaranteed Pods. | `None`, `Static` (needs `reservedMemory` = kube + system reserved + eviction threshold) |
| **Device manager** | Device plugin resources (GPUs…) with NUMA hints. | – |
| **Topology manager** | Collects NUMA **hints** from the others and admits the Pod only if they can align. | `none`, `best-effort`, `restricted`, `single-numa-node`; scope `container` or `pod` |
| **Pod-level** (`PodLevelResourceManagers`, beta, off) | Uses `spec.resources` (pod-level) for exclusive allocation. See `../pod-level-resource-managers`. | |

---

## Step 1
```bash
cd concepts/resource-management/resource-managers
./start-rm-lab.sh
kubectl --context rm-lab get --raw /api/v1/nodes/rm-lab/proxy/configz | jq -c '.kubeletconfig | {cpuManagerPolicy, reservedSystemCPUs, memoryManagerPolicy, reservedMemory, topologyManagerPolicy}'
#   {"cpuManagerPolicy":"static","reservedSystemCPUs":"0","memoryManagerPolicy":"Static","reservedMemory":[{"numaNode":0,"limits":{"memory":"512Mi"}}],"topologyManagerPolicy":"best-effort"}
```
The docker-driver node sees the **host's** 8 CPUs, one NUMA node. Allocatable CPU = 7 (CPU 0 reserved).

## Lab 1 – Who gets exclusive CPUs (the docs' six examples)
```bash
kubectl --context rm-lab create ns rm-demo
./make-pods.sh | kubectl --context rm-lab apply -n rm-demo -f -
for p in $(kubectl --context rm-lab get pods -n rm-demo -o name); do echo "$p $(kubectl --context rm-lab exec -n rm-demo $p -- grep Cpus_allowed_list /proc/self/status)"; done
```
| Pod (docs example) | QoS | CPUs |
|---|---|---|
| besteffort | BestEffort | `0,3-7` shared pool |
| burstable-mem | Burstable | `0,3-7` shared |
| burstable-cpu (1 → 2) | Burstable | `0,3-7` shared |
| **guaranteed-int** (2 = 2) | Guaranteed | **`1-2` exclusive** |
| guaranteed-fraction (1.5) | Guaranteed | `0,3-7` shared: fractional CPUs never get exclusivity |
| **guaranteed-limits-only** (limits 2 → requests defaulted to 2) | Guaranteed | **`3-4` exclusive** (once it fit, see below) |
```bash
minikube -p rm-lab ssh -- "sudo cat /var/lib/kubelet/cpu_manager_state" | jq -c '{defaultCpuSet, entries}'
#   {"defaultCpuSet":"0,5-7","entries":{"<uid>":{"nginx":"1-2"},"<uid>":{"nginx":"3-4"}}}       <- checkpoint file
```
`guaranteed-limits-only` was first **Pending** (`Insufficient cpu`, 7 allocatable): the six Pods plus system Pods asked for more than that. Deleting `burstable-cpu` let it in. Right after that, `besteffort` still reported `0,3-7`: the kubelet shrinks the shared pool of running containers on its periodic reconcile, not instantly.

## Lab 2 – Memory manager: NUMA-pinned memory for Guaranteed Pods
```bash
minikube -p rm-lab ssh -- "sudo cat /var/lib/kubelet/memory_manager_state" | jq -c '.entries | to_entries[] | {pod: .key, c: [.value | to_entries[] | {(.key): [.value[] | {type, size, numaAffinity}]}]}'
#   {"c":[{"nginx":[{"type":"memory","size":209715200,"numaAffinity":[0]}]}]}       <- each Guaranteed container (incl. the 1.5-CPU one)
#   {"c":[{"kindnet-cni":[{"type":"memory","size":52428800,"numaAffinity":[0]}]}]}  <- system DaemonSets that are Guaranteed too
```
`machineState` shows `systemReserved: 536870912` = the 512Mi `reservedMemory`. With one NUMA node every affinity is `[0]`; on multi-socket servers this is what keeps memory local to the Pod's CPUs.

---

## Useful commands
```bash
kubectl exec <pod> -- grep -E 'Cpus_allowed_list|Mems_allowed_list' /proc/self/status
minikube -p rm-lab ssh -- "sudo cat /var/lib/kubelet/cpu_manager_state /var/lib/kubelet/memory_manager_state"
kubectl get --raw /api/v1/nodes/<n>/proxy/configz | jq '.kubeletconfig | {cpuManagerPolicy, cpuManagerPolicyOptions, topologyManagerPolicy, topologyManagerScope}'
```

## Cleanup
```bash
./cleanup.sh             # namespace on rm-lab; stop the profile after ../pod-level-resource-managers
```
