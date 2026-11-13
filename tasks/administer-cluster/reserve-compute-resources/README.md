# Reserve Compute Resources for System Daemons – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/

> This applies the docs' **Example Scenario** to a real kubelet on a throwaway profile **`reserve-lab`** (8 CPUs, ~30.35 GiB, ~239 GiB disk) and checks Allocatable against the formula. [kubelet-scenario-docs.yaml](kubelet-scenario-docs.yaml) holds the scenario's three settings **verbatim**. The kubelet rejects its `evictionHard` form, so [kubelet-scenario-fixed.yaml](kubelet-scenario-fixed.yaml) is the working version. Node commands use [../kubeadm/node.sh](../kubeadm/node.sh).

## Key ideas (read first)

```
Allocatable = Capacity - kubeReserved - systemReserved - evictionHard thresholds
```

| Setting | Meaning |
|---|---|
| `kubeReserved` / `systemReserved` | Resources set aside for Kubernetes daemons (kubelet, runtime) and OS daemons (sshd, udev, ...). By default they are only **subtracted from Allocatable**, not enforced. |
| `evictionHard` | Thresholds at which the kubelet evicts Pods. They are also subtracted from Allocatable. |
| `reservedSystemCPUs` | An explicit CPU list for the system. Its CPU count **replaces** the CPU parts of kube/systemReserved. It can't be combined with the reserved cgroups. |
| `enforceNodeAllocatable` | `pods` (default): the `kubepods` cgroup is capped at Capacity - kube - system (eviction **not** subtracted). Adding `system-reserved` / `kube-reserved` also **caps those daemons' cgroups**, which requires `systemReservedCgroup` / `kubeReservedCgroup`. |
| **Caution** | Enforcing `systemReserved` can OOM-kill critical OS daemons. Enforce it only after profiling them. |

---

## Step 0
```bash
cd tasks/administer-cluster/reserve-compute-resources
minikube start -p reserve-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
N(){ P=reserve-lab ../kubeadm/node.sh "$1"; }; K="kubectl --context reserve-lab"
$K get node reserve-lab -o jsonpath='{.status.capacity}{"\n"}{.status.allocatable}{"\n"}'
#   capacity    {"cpu":"8","ephemeral-storage":"256891535360",...,"memory":"31826084Ki","pods":"110"}
#   allocatable {"cpu":"8","ephemeral-storage":"256891535360",...,"memory":"31826084Ki","pods":"110"}   <- nothing reserved
N 'cp /var/lib/kubelet/config.yaml /root/kubelet-config.orig.yaml; grep -A3 ^evictionHard /var/lib/kubelet/config.yaml; cat /sys/fs/cgroup/kubepods.slice/memory.max'
#   evictionHard: imagefs.available: 0%  nodefs.available: 0%  nodefs.inodesFree: 0%      <- minikube disables eviction
#   32589910016                                                                            <- kubepods may use all memory
```

## Lab 1 – The docs' scenario, verbatim
```bash
minikube -p reserve-lab cp kubelet-scenario-docs.yaml /tmp/scenario.yaml
N 'sed -i "/^evictionHard:/,/^  nodefs.inodesFree/d" /var/lib/kubelet/config.yaml; grep -v "^#" /tmp/scenario.yaml >> /var/lib/kubelet/config.yaml
   systemctl restart kubelet; sleep 8; journalctl -u kubelet --since "-10s" | grep "command failed"'
#   "command failed" err="failed to run Kubelet: quantities must match the regular expression '^([+-]?[0-9.]+)([eEinumkKMGTP]*[-+]?[0-9]*)$'"
```
The `<` is flag syntax (`--eviction-hard=memory.available<500Mi`). In a config file the value is a plain quantity:
```bash
N 'sed -i "s/^evictionHard: .*/evictionHard: {memory.available: \"500Mi\", nodefs.available: \"10%\"}/" /var/lib/kubelet/config.yaml
   systemctl reset-failed kubelet; systemctl restart kubelet'
$K get node reserve-lab -o jsonpath='cpu={.status.allocatable.cpu} mem={.status.allocatable.memory} eph={.status.allocatable.ephemeral-storage}{"\n"}'
#   cpu=6500m mem=28168356Ki eph=229054897794
```
| | Capacity | − kube | − system | − eviction | = Allocatable |
|---|---|---|---|---|---|
| CPU | 8 | 1 | 0.5 | – | **6.5** ✔ |
| Memory | 31826084Ki | 2Gi | 1Gi | 500Mi | **28168356Ki** ✔ |
| Disk | 256891535360 | 1Gi | 1Gi | 10% | **≈229054898176** ✔ (rounding) |

The docs' 32Gi/16 CPU/100Gi node gives 14.5 CPUs / 28.5Gi / 88Gi by the same arithmetic.

## Lab 2 – What `pods` enforcement means
```bash
N 'cat /sys/fs/cgroup/kubepods.slice/memory.max'
#   29368684544      = 32589910016 - 2Gi - 1Gi   <- capacity minus kube- and system-reserved, NOT minus the eviction threshold
```
So all Pods together are hard-capped at Capacity − reservations. Eviction starts earlier, at Allocatable.

## Lab 3 – Enforcing `system-reserved`
```bash
N 'cp /var/lib/kubelet/config.yaml /root/kubelet-config.scenario.yaml
   printf "enforceNodeAllocatable: [pods,system-reserved]\n" >> /var/lib/kubelet/config.yaml; systemctl restart kubelet; sleep 6
   journalctl -u kubelet --since "-7s" | grep "command failed"'
#   err="... invalid configuration: systemReservedCgroup (--system-reserved-cgroup) must be specified when \"system-reserved\" ... "
N 'printf "systemReservedCgroup: /system.slice\n" >> /var/lib/kubelet/config.yaml; systemctl reset-failed kubelet; systemctl restart kubelet; sleep 8
   cat /sys/fs/cgroup/system.slice/memory.max'
#   1073741824          <- containerd, sshd, ... (system.slice) are now limited to systemReserved = 1Gi
```
The kubelet doesn't create that cgroup. It must already exist; with systemd, `system.slice` does.

## Lab 4 – `reservedSystemCPUs`
```bash
N 'cp /root/kubelet-config.scenario.yaml /var/lib/kubelet/config.yaml; printf "reservedSystemCPUs: \"0-1\"\n" >> /var/lib/kubelet/config.yaml; systemctl restart kubelet'
$K get node reserve-lab -o jsonpath='{.status.allocatable.cpu}{"\n"}'      # 6   <- 2 CPUs reserved, replacing 1000m + 500m
N 'printf "systemReservedCgroup: /system.slice\nenforceNodeAllocatable: [pods,system-reserved]\n" >> /var/lib/kubelet/config.yaml; systemctl restart kubelet; sleep 6
   journalctl -u kubelet --since "-7s" | grep "command failed"'
#   err="... can't use reservedSystemCPUs (--reserved-cpus) with systemReservedCgroup (--system-reserved-cgroup) or kubeReservedCgroup ..."
```

---

## Useful commands
```bash
kubectl get node <n> -o jsonpath='{.status.capacity}{"\n"}{.status.allocatable}{"\n"}'
kubectl describe node <n> | grep -A8 Allocatable
cat /sys/fs/cgroup/kubepods.slice/memory.max /sys/fs/cgroup/system.slice/memory.max
```

## Cleanup
```bash
minikube delete -p reserve-lab
```
