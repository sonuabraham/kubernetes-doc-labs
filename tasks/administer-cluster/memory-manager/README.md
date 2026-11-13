# Control Memory Management Policies on a Node – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/memory-manager/

> This runs on the throwaway profile **`nodepol-lab`** from [../cpu-management-policies](../cpu-management-policies/). The node has 1 NUMA node and ~31 GiB. The docs' two Guaranteed-Pod excerpts are used with their `spec` **verbatim**, wrapped in full manifests: [01-guaranteed-integer-cpu.yaml](01-guaranteed-integer-cpu.yaml) and [02-guaranteed-shared-cpu.yaml](02-guaranteed-shared-cpu.yaml). Node commands use [../kubeadm/node.sh](../kubeadm/node.sh).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Memory Manager** | A kubelet hint provider. For **Guaranteed** Pods it reserves memory (and hugepages) on specific **NUMA nodes**, reports that as a topology hint to the Topology Manager, and pins the container's `cpuset.mems`. |
| **Policies** | `None` (default, no effect), `Static` (Linux: guarantees for Guaranteed Pods), `BestEffort` (Windows only). |
| **Must reserve** | `Static` requires `reservedMemory` per NUMA node, and the **sum must equal** `kubeReserved + systemReserved + evictionHard[memory.available]`. Otherwise the kubelet won't start. |
| **State** | `/var/lib/kubelet/memory_manager_state`: machine state (per-NUMA memory map) plus entries per Pod UID/container. Changing the policy means stop the kubelet, delete the file, and start again (like the CPU manager). |
| **Alignment** | For CPU + memory + device alignment, also enable the CPU manager (`static`) and a Topology Manager policy. |

---

## Step 0 – the profile, back to defaults
```bash
cd tasks/administer-cluster/memory-manager
N(){ P=nodepol-lab ../kubeadm/node.sh "$1"; }; K="kubectl --context nodepol-lab"
N 'systemctl stop kubelet; cp /root/kubelet-config.orig.yaml /var/lib/kubelet/config.yaml; rm /var/lib/kubelet/cpu_manager_state; systemctl start kubelet'
N 'cat /var/lib/kubelet/memory_manager_state; ls /sys/devices/system/node/ | grep node; grep -A4 evictionHard /var/lib/kubelet/config.yaml'
#   {"policyName":"None","machineState":{}, ...}
#   node0                                               <- one NUMA node
#   evictionHard: imagefs.available: 0%  nodefs.available: 0%  nodefs.inodesFree: 0%     <- no memory.available!
```

## Lab 1 – Static without reserved memory
```bash
N 'systemctl stop kubelet; rm /var/lib/kubelet/memory_manager_state /var/lib/kubelet/cpu_manager_state
   printf "cpuManagerPolicy: static\nreservedSystemCPUs: \"0\"\nmemoryManagerPolicy: Static\n" >> /var/lib/kubelet/config.yaml
   systemctl start kubelet; sleep 6; journalctl -u kubelet --since "-8s" | grep "command failed"'
#   "command failed" err="failed to run Kubelet: [memorymanager] you should specify the system reserved memory"
```

## Lab 2 – The reservation formula
```bash
N 'printf "kubeReserved: {cpu: \"500m\", memory: \"50Mi\"}\nsystemReserved: {cpu: \"500m\", memory: \"256Mi\"}\nreservedMemory:\n- numaNode: 0\n  limits:\n    memory: \"1Gi\"\n" >> /var/lib/kubelet/config.yaml
   systemctl reset-failed kubelet; systemctl restart kubelet; sleep 6; journalctl -u kubelet --since "-7s" | grep "command failed"'
#   err="failed to run Kubelet: the total amount \"1Gi\" of type \"memory\" is not equal to the value \"306Mi\" determined by Node Allocatable feature"
```
306Mi = kubeReserved 50Mi + systemReserved 256Mi + eviction **0**. The docs warn that the hard-eviction default is 100Mi. That applies when `evictionHard` is left unset. minikube sets `evictionHard` without `memory.available`, so here it counts as 0.
```bash
N 'sed -i "s/    memory: \"1Gi\"/    memory: \"306Mi\"/" /var/lib/kubelet/config.yaml; systemctl reset-failed kubelet; systemctl restart kubelet; sleep 8; systemctl is-active kubelet'
#   active
N 'python3 -c "import json;d=json.load(open(\"/var/lib/kubelet/memory_manager_state\"));print(d[\"policyName\"], d[\"machineState\"][\"0\"][\"memoryMap\"][\"memory\"])"'
#   Static {'total': 32589910016, 'systemReserved': 320864256, 'allocatable': 32269045760, 'reserved': ..., 'free': ...}
#                                  ^ 306Mi
$K get node nodepol-lab -o jsonpath='{.status.allocatable.memory} of {.status.capacity.memory}{"\n"}'
#   31512740Ki of 31826084Ki          <- 306Mi less
```
Another configuration to avoid, a NUMA node that doesn't exist:
```bash
#   reservedMemory: [{numaNode: 0, limits: {memory: 206Mi}}, {numaNode: 1, limits: {memory: 100Mi}}]
#   err="failed to run Kubelet: the reserved memory configuration references a NUMA node 1 that does not exist on this machine"
```

## Lab 3 – Guaranteed Pods (the docs' excerpts)
Both request `example.com/device: "1"`, so advertise two devices on the node first (see [../extended-resource-node](../extended-resource-node/)):
```bash
$K patch node nodepol-lab --subresource=status --type=json -p '[{"op":"add","path":"/status/capacity/example.com~1device","value":"2"}]'
$K create ns mem-demo
$K apply -f 01-guaranteed-integer-cpu.yaml -f 02-guaranteed-shared-cpu.yaml
for p in guaranteed-integer-cpu guaranteed-shared-cpu; do echo "$p qos=$($K -n mem-demo get po $p -o jsonpath='{.status.qosClass}') \
  cpus=$($K -n mem-demo exec $p -- cat /sys/fs/cgroup/cpuset.cpus.effective) mems=$($K -n mem-demo exec $p -- cat /sys/fs/cgroup/cpuset.mems.effective)"; done
#   guaranteed-integer-cpu qos=Guaranteed cpus=3-4 mems=0          <- exclusive CPUs + memory pinned to NUMA 0
#   guaranteed-shared-cpu qos=Guaranteed cpus=0-2,5-7 mems=0       <- shared CPU pool, memory still guaranteed on NUMA 0
N 'python3 -c "import json;d=json.load(open(\"/var/lib/kubelet/memory_manager_state\"));[print(p[:8],c,b) for p,cs in d[\"entries\"].items() for c,b in cs.items()]"'
#   fe470f83 nginx [{'numaAffinity': [0], 'type': 'memory', 'size': 209715200}]   <- 200Mi each
#   56d8cb5a nginx [{'numaAffinity': [0], 'type': 'memory', 'size': 209715200}]
#   d29dd72e kindnet-cni [{'numaAffinity': [0], 'type': 'memory', 'size': 52428800}]   <- kindnet is Guaranteed too
```
(Entries are keyed by Pod UID. Pods that were still terminating while the state file was recreated can leave stale entries for a while.)

---

## Useful commands
```bash
cat /var/lib/kubelet/memory_manager_state
kubectl exec <pod> -- cat /sys/fs/cgroup/cpuset.mems.effective
ls /sys/devices/system/node/ ; numactl -H                 # NUMA layout
```

## Cleanup
```bash
$K delete ns mem-demo
$K patch node nodepol-lab --subresource=status --type=json -p '[{"op":"remove","path":"/status/capacity/example.com~1device"}]'
# back to defaults (stop, restore config, drop both state files, start), or: minikube delete -p nodepol-lab
```
