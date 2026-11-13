# Control Topology Management Policies on a node – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/topology-manager/

> This runs on the throwaway profile **`nodepol-lab`**, continuing from [../memory-manager](../memory-manager/): CPU manager `static` (CPU 0 reserved) and memory manager `Static` (306Mi reserved) are already on. The docs' five Pod examples are used with their `spec` **verbatim**, wrapped in full manifests ([01](01-besteffort.yaml)–[05](05-besteffort-devices.yaml)).
>
> ⚠️ This node has a **single NUMA node**, so every hint resolves to node 0 and no policy can reject a Pod here. The lab shows configuration, scope, validation and the hints each provider reports (`--v=4` kubelet logs). Rejection (`TopologyAffinityError`) needs a multi-NUMA machine.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Topology Manager** | A kubelet component that collects **NUMA hints** from the *hint providers* (CPU manager, memory manager, device manager) and decides admission and alignment. |
| **Policies** | `none` (default, no alignment) · `best-effort` (prefer aligned, always admit) · `restricted` (admit only preferred alignment) · `single-numa-node` (admit only if everything fits **one** NUMA node). Rejected Pods end up `Terminated` with `TopologyAffinityError` and are **not** rescheduled, so use controllers. |
| **Scope** | `container` (default: align each container separately) or `pod` (align the whole Pod's resources together, the same decision for every container). |
| **Options** | `prefer-closest-numa-nodes` (GA), `max-allowable-numa-nodes` (GA, >8 NUMA nodes). Unknown options stop the kubelet. |
| **Hint format** | `NUMANodeAffinity` is a **bitmask**: `1` = node 0, `2` = node 1, `3` = nodes 0+1. `null` means "any". |
| **Who gives hints** | CPU manager: only for exclusive (integer CPU, Guaranteed) requests. Memory manager: Guaranteed Pods. Device manager: devices from **device plugins** that report topology. |
| **Limitation** | The scheduler isn't topology-aware: a Pod can be scheduled to a node and then rejected by the kubelet there. |

---

## Step 0 – policy + scope (kubelet config)
```bash
cd tasks/administer-cluster/topology-manager
N(){ P=nodepol-lab ../kubeadm/node.sh "$1"; }; K="kubectl --context nodepol-lab"
N 'printf "topologyManagerPolicy: single-numa-node\ntopologyManagerScope: pod\n" >> /var/lib/kubelet/config.yaml
   sed -i "s/^  verbosity: 0/  verbosity: 4/" /var/lib/kubelet/config.yaml
   systemctl restart kubelet; sleep 8; journalctl -u kubelet --since "-10s" | grep "Creating topology manager"'
#   topology_manager.go:192] "Creating topology manager with policy per scope" topologyPolicyName="single-numa-node"
#                            topologyScopeName="pod" topologyPolicyOptions={"PreferClosestNUMA":false,...}
```

## Lab 1 – The docs' five Pods
`example.com/device`, `deviceA` and `deviceB` must exist on the node. Here they're **patched-in** extended resources (see [../extended-resource-node](../extended-resource-node/)), not device-plugin devices:
```bash
$K patch node nodepol-lab --subresource=status --type=json -p '[{"op":"add","path":"/status/capacity/example.com~1device","value":"2"},{"op":"add","path":"/status/capacity/example.com~1deviceA","value":"1"},{"op":"add","path":"/status/capacity/example.com~1deviceB","value":"1"}]'
$K create ns topo-demo
$K apply -f .
$K -n topo-demo get po -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass,STATUS:.status.phase
#   besteffort               BestEffort   Running
#   besteffort-devices       BestEffort   Running
#   burstable                Burstable    Running
#   guaranteed-integer-cpu   Guaranteed   Running
#   guaranteed-shared-cpu    Guaranteed   Running
```

## Lab 2 – What each hint provider said
```bash
N 'journalctl -u kubelet --since "-5min" | grep -E "\"(TopologyHints|Best TopologyHint)\"" | grep topo-demo/guaranteed | sed -E "s/^.*\] //"'
#   "TopologyHints" hints={}                                               pod="topo-demo/guaranteed-integer-cpu"   <- device manager: no device plugin, no topology
#   "TopologyHints" hints={"cpu":[{"NUMANodeAffinity":1,"Preferred":true}]}    ...guaranteed-integer-cpu  <- CPU manager: 2 exclusive CPUs on node 0
#   "TopologyHints" hints={"memory":[{"NUMANodeAffinity":1,"Preferred":true}]} ...guaranteed-integer-cpu  <- memory manager
#   "Best TopologyHint" bestHint={"NUMANodeAffinity":null,"Preferred":true}    ...guaranteed-integer-cpu
#   "TopologyHints" hints={}                                               pod="topo-demo/guaranteed-shared-cpu"
#   "TopologyHints" hints=null                                             ...guaranteed-shared-cpu   <- 300m CPU: CPU manager has no preference
#   "TopologyHints" hints={"memory":[{"NUMANodeAffinity":1,"Preferred":true}]} ...guaranteed-shared-cpu
N 'journalctl -u kubelet --since "-5min" | grep "topo-demo/besteffort\"" | sed -E "s/^.*\] //"'
#   "Topology manager admission check" ... "TopologyHints" hints={} / null / null
#   "Best TopologyHint" bestHint={"NUMANodeAffinity":null,"Preferred":true}
#   "Resource alignment at pod scope guaranteed"   "Pod Admit Result" Message=""
```
This matches the page's walkthrough: BestEffort and Burstable Pods get default hints, the integer-CPU Guaranteed Pod gets a CPU hint, and the shared-CPU one doesn't. With real device-plugin devices, the device manager would add per-device hints. On a 2-NUMA machine, `single-numa-node` would reject a Pod whose CPUs, memory and devices can't all come from one node.

## Lab 3 – Policy options are validated
```bash
N 'printf "topologyManagerPolicyOptions:\n  prefer-closest-numa-nodes: \"true\"\n  no-such-option: \"true\"\n" >> /var/lib/kubelet/config.yaml; systemctl restart kubelet; sleep 6
   journalctl -u kubelet --since "-7s" | grep "command failed"'
#   "command failed" err="failed to run Kubelet: unknown Topology Manager Policy option: \"no-such-option\""
N 'sed -i "/no-such-option/d" /var/lib/kubelet/config.yaml; systemctl reset-failed kubelet; systemctl restart kubelet; sleep 8
   journalctl -u kubelet --since "-10s" | grep -o "topologyPolicyOptions={[^}]*}"'
#   topologyPolicyOptions={"PreferClosestNUMA":true,"MaxAllowableNUMANodes":8}
```

---

## Useful commands
```bash
grep -E "^topology|^cpuManager|^memoryManager" /var/lib/kubelet/config.yaml
journalctl -u kubelet | grep -E "TopologyHints|Best TopologyHint|Topology Affinity|TopologyAffinityError"
kubectl get pods -A --field-selector=status.phase=Failed -o custom-columns=NAME:.metadata.name,REASON:.status.reason   # rejected Pods
```

## Cleanup
```bash
minikube delete -p nodepol-lab
```
