# Control CPU Management Policies on the Node – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/cpu-management-policies/

> This runs on a throwaway profile **`nodepol-lab`** (minikube, 8 host CPUs visible; each CPU is its own core and there is no SMT). [01-cpu-pods.yaml](01-cpu-pods.yaml) has three Pods that print the CPUs they may use, and [show.sh](show.sh) collects the result. Node commands use [../kubeadm/node.sh](../kubeadm/node.sh). The same profile is reused by [../memory-manager](../memory-manager/) and [../topology-manager](../topology-manager/).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`none`** (default) | Every container may run on every CPU. Limits are enforced with CFS quota (throttling), and threads migrate between cores. |
| **`static`** | The kubelet hands out **exclusive CPUs** (cpusets) to containers of **Guaranteed** Pods with **integer** CPU requests. Everything else, including Guaranteed Pods with fractional CPU, shares the remaining **shared pool**. |
| **Reservation required** | `static` needs CPU reserved for the system (`reservedSystemCPUs`, or `kubeReserved`/`systemReserved` CPU). Otherwise the kubelet won't start. |
| **Changing policy** | Applies only to new admissions, and the checkpoint `/var/lib/kubelet/cpu_manager_state` must match. Drain → stop kubelet → **delete the state file** → edit config → start. |
| **Policy options** | `cpuManagerPolicyOptions`: `full-pcpus-only` (whole physical cores, SMT siblings together), `distribute-cpus-across-numa`, `strict-cpu-reservation` (keep reserved CPUs out of the shared pool too), `prefer-align-cpus-by-uncorecache`, plus alpha ones behind `CPUManagerPolicyAlphaOptions`. |

---

## Step 0
```bash
cd tasks/administer-cluster/cpu-management-policies
minikube start -p nodepol-lab --memory 3000 --cpus 4 --kubernetes-version v1.37.0 && kubectl config use-context minikube
N(){ P=nodepol-lab ../kubeadm/node.sh "$1"; }
kubectl --context nodepol-lab get node nodepol-lab -o jsonpath='{.status.capacity.cpu}{"\n"}'      # 8 (--cpus is a quota, not a cpuset)
N 'cat /var/lib/kubelet/cpu_manager_state; lscpu -e=CPU,CORE,SOCKET,NODE'
#   {"policyName":"none","defaultCpuSet":"", ...}
#   CPU CORE SOCKET NODE:  0 0 0 0 / 1 1 0 0 / ... / 7 7 0 0      <- 8 cores, no hyperthreads, 1 NUMA node
N 'cp /var/lib/kubelet/config.yaml /root/kubelet-config.orig.yaml'
```

## Lab 1 – Policy `none`
```bash
kubectl --context nodepol-lab apply -f 01-cpu-pods.yaml
./show.sh
#   guaranteed-int       Guaranteed  cpuset=0-7
#   guaranteed-fraction  Guaranteed  cpuset=0-7
#   burstable            Burstable   cpuset=0-7
```

## Lab 2 – Switching the wrong way
```bash
N 'printf "cpuManagerPolicy: static\n" >> /var/lib/kubelet/config.yaml; systemctl restart kubelet; sleep 8; journalctl -u kubelet --since "-10s" | grep "command failed"'
#   "command failed" err="failed to run Kubelet: [cpumanager] unable to determine reserved CPU resources for static policy"
N 'printf "reservedSystemCPUs: \"0\"\n" >> /var/lib/kubelet/config.yaml; systemctl restart kubelet'
sleep 60; N 'journalctl -u kubelet --since "-1min" | grep "differs from state checkpoint" | tail -1'
#   "Could not initialize checkpoint manager, please drain node and remove policy state file" err="could not restore
#    state from checkpoint: configured policy \"static\" differs from state checkpoint policy \"none\", please drain this
#    node and delete the CPU manager checkpoint file \"/var/lib/kubelet/cpu_manager_state\" before restarting Kubelet"
```

## Lab 3 – The documented procedure
On a real node, drain first. Here it's a single node whose kubelet is crashlooping, so the demo Pods are just recreated afterwards.
```bash
N 'systemctl stop kubelet; rm /var/lib/kubelet/cpu_manager_state; systemctl start kubelet; sleep 10; cat /var/lib/kubelet/cpu_manager_state'
#   {"policyName":"static","defaultCpuSet":"0,3-7","entries":{"48e0...":{"app":"1-2"}}, ...}
#        <- the still-running guaranteed-int container was re-admitted and pinned to 1-2
kubectl --context nodepol-lab delete ns cpu-demo; kubectl --context nodepol-lab apply -f 01-cpu-pods.yaml
./show.sh
#   guaranteed-int       Guaranteed  cpuset=1-2       <- exclusive: 2 whole CPUs
#   guaranteed-fraction  Guaranteed  cpuset=0,3-7     <- 500m: shared pool
#   burstable            Burstable   cpuset=0,3-7     <- shared pool (includes reserved CPU 0)
```

## Lab 4 – Policy option `strict-cpu-reservation`
```bash
kubectl --context nodepol-lab delete ns cpu-demo
N 'printf "cpuManagerPolicyOptions:\n  strict-cpu-reservation: \"true\"\n" >> /var/lib/kubelet/config.yaml
   systemctl stop kubelet; rm /var/lib/kubelet/cpu_manager_state; systemctl start kubelet'
kubectl --context nodepol-lab apply -f 01-cpu-pods.yaml; ./show.sh
#   guaranteed-int       Guaranteed  cpuset=1-2
#   guaranteed-fraction  Guaranteed  cpuset=3-7       <- reserved CPU 0 is now off-limits to Pods entirely
#   burstable            Burstable   cpuset=3-7
```
`full-pcpus-only` would reject Guaranteed containers that don't fill whole physical cores (`SMTAlignmentError`). This node has no SMT siblings, so every CPU *is* a full core and nothing would be rejected.

---

## Useful commands
```bash
cat /var/lib/kubelet/cpu_manager_state
kubectl exec <pod> -- cat /sys/fs/cgroup/cpuset.cpus.effective
grep -E "cpuManager|reserved" /var/lib/kubelet/config.yaml
```

## Cleanup
```bash
kubectl --context nodepol-lab delete ns cpu-demo
# restore the kubelet config if you continue with the memory/topology labs on this profile:
N 'systemctl stop kubelet; cp /root/kubelet-config.orig.yaml /var/lib/kubelet/config.yaml; rm /var/lib/kubelet/cpu_manager_state; systemctl start kubelet'
# or: minikube delete -p nodepol-lab
```
