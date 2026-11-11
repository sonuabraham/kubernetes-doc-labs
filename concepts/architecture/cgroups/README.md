# About cgroup v2 – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/architecture/cgroups/

> Cluster: the **`arch-lab`** profile (see [../README.md](../README.md)). Pods are pinned to the control-plane node `arch-lab`. The commands work the same on the single-node `minikube` profile if you change `nodeName` and `-p`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **cgroups** | Linux control groups limit the resources of a group of processes. The kubelet and the container runtime use them to enforce pod/container **requests and limits**. |
| **cgroup v2** | Stable in Kubernetes since v1.25. A single **unified hierarchy**, safer delegation to containers, **PSI** (Pressure Stall Information), and unified accounting for kernel, network and page-cache memory. Features such as **MemoryQoS** need v2. |
| **Requirements** | A distro with v2 enabled, kernel **≥ 5.8**, a runtime with v2 support (containerd ≥ 1.4, CRI-O ≥ 1.20), and kubelet + runtime both on the **systemd cgroup driver**. |
| **Check** | `stat -fc %T /sys/fs/cgroup/` prints `cgroup2fs` on v2 and `tmpfs` on v1. |
| **Migration** | The kubelet detects v2 automatically. Only software that reads the cgroup filesystem directly must be v2-aware: monitoring agents, cAdvisor ≥ 0.43, JDK 8u372 / 11.0.16 / 15+, automaxprocs ≥ 1.5.1, Node.js ≥ 20.3. |
| **v1 deprecated** | Deprecated since v1.35. The kubelet **refuses to start** on a v1 node unless `failCgroupV1: false` is set. |
| **Limits → files** | CPU limit → `cpu.max` (quota/period). CPU request → `cpu.weight`. Memory limit → `memory.max`. Exceeding `memory.max` means an OOM kill. Exceeding `cpu.max` means **throttling**. |

## The demo app
[00-demo-app.yaml](00-demo-app.yaml) is namespace `cgroups-demo` with pod `limited` (requests 100m/32Mi, limits 250m/64Mi) and pod `cpu-burner` (limit 100m, spinning). [01-oom.yaml](01-oom.yaml) is a pod that outgrows its 64Mi limit.

---

## Step 1
```bash
cd concepts/architecture/cgroups
kubectl config use-context arch-lab
kubectl apply -f 00-demo-app.yaml
kubectl wait --for=condition=Ready pod/limited pod/cpu-burner -n cgroups-demo
```

## Lab 1 – Which cgroup version? (the docs command, at three levels)
```bash
stat -fc %T /sys/fs/cgroup/                                             # your laptop:   cgroup2fs
minikube ssh -p arch-lab -n arch-lab -- stat -fc %T /sys/fs/cgroup/     # the node:      cgroup2fs
kubectl exec limited -n cgroups-demo -- grep cgroup /proc/mounts       # the container: cgroup /sys/fs/cgroup cgroup2 ro,...
```
(busybox's `stat` prints `UNKNOWN` for cgroup2, so the container check reads `/proc/mounts`.)

## Lab 2 – The requirements on this node
```bash
minikube ssh -p arch-lab -n arch-lab -- 'uname -r; containerd --version'
#   7.0.0-38-generic  (>= 5.8)      containerd v2.3.4 (>= 1.4)
minikube ssh -p arch-lab -n arch-lab -- 'sudo grep -E "cgroupDriver|failCgroupV1" /var/lib/kubelet/config.yaml; sudo grep SystemdCgroup /etc/containerd/config.toml'
#   cgroupDriver: systemd           SystemdCgroup = true      <- both on the systemd driver
```
`failCgroupV1` isn't set, so the default `true` applies: this kubelet would refuse to start on a cgroup v1 node.

## Lab 3 – Requests and limits become cgroup files
```bash
kubectl exec limited -n cgroups-demo -- sh -c 'for f in cpu.max cpu.weight memory.max memory.high; do printf "%-12s %s\n" $f "$(cat /sys/fs/cgroup/$f)"; done'
```
Expected:
```
cpu.max      25000 100000       <- limit 250m = 25ms of CPU per 100ms period
cpu.weight   17                 <- request 100m, converted to a relative weight
memory.max   67108864           <- limit 64Mi
memory.high  max
```
The pod-level cgroups on the node, grouped by **QoS class** (unified hierarchy):
```bash
kubectl get pod limited -n cgroups-demo -o jsonpath='{.status.qosClass}{"\n"}'          # Burstable
minikube ssh -p arch-lab -n arch-lab -- 'ls -d /sys/fs/cgroup/kubepods.slice/*/'
#   kubepods-besteffort.slice/  kubepods-burstable.slice/  kubepods-pod<uid>.slice/ (Guaranteed pods sit directly under kubepods)
U=$(kubectl get pod limited -n cgroups-demo -o jsonpath='{.metadata.uid}' | tr - _)
minikube ssh -p arch-lab -n arch-lab -- "cat /sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod$U.slice/memory.max"
```
Why apps must be cgroup-aware:
```bash
kubectl exec limited -n cgroups-demo -- free -m | head -2      # total ~31000 MB - the HOST's memory, not 64Mi!
```
An old JVM or Node.js sizes its heap from that number and gets OOM-killed. That's the docs' migration warning.

## Lab 4 – CPU throttling and PSI (a v2-only feature)
```bash
sleep 10
kubectl exec cpu-burner -n cgroups-demo -- sh -c 'cat /sys/fs/cgroup/cpu.max; grep -E "nr_throttled|throttled_usec" /sys/fs/cgroup/cpu.stat; cat /sys/fs/cgroup/cpu.pressure'
```
Expected:
```
10000 100000                                  <- 100m
nr_throttled 46
throttled_usec 1327759                        <- the kernel paused it to enforce the limit
some avg10=53.32 avg60=12.77 avg300=2.80 ...  <- PSI: tasks waited for CPU ~53% of the last 10s
full avg10=53.32 ...
```
PSI (`cpu.pressure`, `memory.pressure`, `io.pressure`) only exists on cgroup v2. It tells you how much **time was lost waiting**, which is a better saturation signal than usage.

## Lab 5 – Memory limit → OOM kill
```bash
kubectl apply -f 01-oom.yaml ; sleep 12
kubectl get pod oom -n cgroups-demo -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} exit={.status.containerStatuses[0].state.terminated.exitCode}{"\n"}'
minikube ssh -p arch-lab -n arch-lab -- "sudo dmesg | grep 'Memory cgroup out of memory' | tail -1"
#   Memory cgroup out of memory: Killed process … (tail) … anon-rss:64888kB …     <- the cgroup's memory.max at work
kubectl exec limited -n cgroups-demo -- cat /sys/fs/cgroup/memory.oom.group      # 1 - OOM kills the whole container, not one process
```
On a normal node the reason is **`OOMKilled`** (exit 137). On minikube's docker driver, containerd runs **inside** a container and doesn't receive the OOM event, so the pod shows `Error exit=137` here. `dmesg` proves it was the kernel's cgroup OOM killer.

---

## Useful commands
```bash
stat -fc %T /sys/fs/cgroup/
kubectl exec <pod> -- cat /sys/fs/cgroup/{cpu.max,memory.max,cpu.stat,memory.events,cpu.pressure}
minikube ssh -- 'systemd-cgls --no-pager | head -40'        # the cgroup tree on the node
kubectl get pod <pod> -o jsonpath='{.status.qosClass}'
```

## Cleanup
```bash
./cleanup.sh
```
