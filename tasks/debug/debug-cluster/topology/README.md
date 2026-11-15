# Troubleshooting Topology Management – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-cluster/topology/

> Runs on the throwaway profile **`topo-lab`**, created by [setup-topo-lab.sh](setup-topo-lab.sh). Its kubelet uses CPU manager `static`,
> Memory Manager `Static` and Topology Manager `single-numa-node`. **Stop the default `minikube` first** (inotify limit).
> This machine has **one** NUMA node, so a `TopologyAffinityError` can't happen on CPU and memory alone. To provoke one, the lab's toy device
> plugin (from [concepts/…/device-plugins](../../../../concepts/extend-kubernetes/compute-storage-net/device-plugins/), now with a `NUMA_NODE`
> setting) reports its devices on NUMA node **1**.
> Files: [guaranteed.yaml](guaranteed.yaml) (docs, **verbatim**). Not from the docs: [guaranteed-fits.yaml](guaranteed-fits.yaml),
> [numa-mismatch.yaml](numa-mismatch.yaml), [toy-plugin-numa1.yaml](toy-plugin-numa1.yaml), [node-topology-state.py](node-topology-state.py).
> Background: [cpu-management-policies](../../../administer-cluster/cpu-management-policies/), [memory-manager](../../../administer-cluster/memory-manager/),
> [topology-manager](../../../administer-cluster/topology-manager/).

## Key ideas (read first)

| Source (from the page) | What you learn |
|---|---|
| **Pod status / events** | `TopologyAffinityError`: the kubelet rejected the Pod at admission. It is *already scheduled*, so the scheduler didn't see the problem. |
| **kubelet log** | each hint provider's hints (`cpu`, `memory`, devices…), the merged `bestHint`, and the policy's verdict |
| **state files** | `/var/lib/kubelet/memory_manager_state` (per NUMA node: total / reserved / free, and per container `numaAffinity`) and `cpu_manager_state` |
| **PodResources API** | the kubelet's gRPC socket: CPUs, memory blocks and devices per container, plus allocatable. Only Guaranteed Pods get CPU/memory entries. |

Hints are **bitmasks** of NUMA nodes: `NUMANodeAffinity: 1` = `0b01` = node 0, `2` = node 1, `3` = both.

---

## Step 0 – The lab node
```bash
cd tasks/debug/debug-cluster/topology
minikube stop
./setup-topo-lab.sh
K="kubectl --context topo-lab"
minikube -p topo-lab ssh -- "ls /sys/devices/system/node | grep node"        # node0   <- one NUMA node
```

## Lab 1 – The docs' Pod
```bash
$K apply -f guaranteed.yaml        # image "consumer", imagePullPolicy Never, 150Gi
$K get pod guaranteed              # Pending
$K get events --field-selector involvedObject.name=guaranteed
#   FailedScheduling  0/1 nodes are available: 1 Insufficient memory. …       <- never reaches the kubelet's topology checks
$K delete pod guaranteed --now
$K apply -f guaranteed-fits.yaml   # the same shape: 2 CPUs, 1Gi, a real image
```

## Lab 2 – Provoke `TopologyAffinityError`
```bash
$K apply -f toy-plugin-numa1.yaml          # 2 toy devices, reported on NUMA node 1, + a PodResources client "monitor"
$K apply -f numa-mismatch.yaml             # Guaranteed: 1 CPU, 512Mi, 1 device
$K get pod numa-mismatch
#   numa-mismatch   0/1   TopologyAffinityError   0   6s
$K get events --field-selector involvedObject.name=numa-mismatch
#   Scheduled               Successfully assigned default/numa-mismatch to topo-lab
#   TopologyAffinityError   Resources cannot be allocated with Topology locality              <- the docs' message
```

## Lab 3 – System logs: the hints (docs)
```bash
minikube -p topo-lab ssh -- "sudo journalctl -u kubelet | grep numa-mismatch | grep -iE 'hint|affinity'"
```
```
"TopologyHints" hints={"hardware-vendor.example/foo":[]}             <- the device can't be on node 0 at all
"TopologyHints generated" … cpuHints=[{"NUMANodeAffinity":1,"Preferred":true}]          <- CPU: node 0
"TopologyHints" hints={"memory":[{"NUMANodeAffinity":1,"Preferred":true}]}               <- memory: node 0
"Best TopologyHint" bestHint={"NUMANodeAffinity":null,"Preferred":false}                 <- merged: no common node
```
`single-numa-node` admits only a preferred hint on one node, so the Pod is rejected.

## Lab 4 – The kubelet state files (docs)
```bash
minikube -p topo-lab cp node-topology-state.py /tmp/node-topology-state.py
minikube -p topo-lab ssh -- sudo python3 /tmp/node-topology-state.py
```
```
memory manager policy: Static
  NUMA 0: total=32589910016 systemReserved=320864256 allocatable=32269045760 reserved=1126170624 free=31142875136 assignments=2 group=[0]
  pod 362d190c container guaranteed: memory 1073741824 bytes numaAffinity=[0]       <- guaranteed-fits, pinned to node 0
  pod d333e27b container kindnet-cni: memory 52428800 bytes numaAffinity=[0]        <- kindnet is Guaranteed too
cpu manager policy: static | shared pool: 0,3-7
  pod 362d190c container guaranteed: exclusive cpus 1-2
```
As in the docs: `systemReserved` 320864256 = 306Mi (`reservedMemory`), and `free` is what's left in that NUMA group. In 1.37 the docs'
`"nodes"` group field is called `"cells"` in the file.

## Lab 5 – The PodResources API (docs)
```bash
$K exec -n topo-demo monitor -- python podresources.py list
#   kube-system/kindnet-…/kindnet-cni: memory memory 52428800 bytes numa=[0]
#   default/guaranteed-fits/guaranteed: exclusive cpus [2, 1]
#   default/guaranteed-fits/guaranteed: memory memory 1073741824 bytes numa=[0]      <- the ContainerMemory message
$K exec -n topo-demo monitor -- python podresources.py allocatable
#   hardware-vendor.example/foo ['foo-0'] numa=[1]
#   hardware-vendor.example/foo ['foo-1'] numa=[1]      <- here is the mismatch
#   cpus [7, 1, 2, 3, 4, 5, 6]
#   memory memory 32269045760 bytes numa=[0]
```

## Step 6 – Back to the default cluster
```bash
./cleanup.sh          # minikube delete -p topo-lab
minikube start
```

## Useful commands
```bash
kubectl get pods --field-selector status.phase=Failed      # admission-rejected Pods end up Failed
minikube -p topo-lab ssh -- "sudo journalctl -u kubelet | grep -E 'Best TopologyHint|TopologyAffinityError'"
```

## Cleanup
```bash
./cleanup.sh
```
