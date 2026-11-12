# Resource Management for Windows Nodes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/configuration/windows-resource-management/

> ⚠️ **Needs Windows nodes**, which minikube can't run. The page has no YAML. This lab checks what the API enforces for Windows Pods and compares the Linux behaviour you *can* see (cgroups, OOM, reservations) with what the page says about Windows.

## Key ideas (read first)

| Topic | Linux | Windows |
|---|---|---|
| **Pod/container boundary** | cgroups (+ namespaces) | a **job object** per container + system namespace filter |
| **Privileged containers** | `privileged: true` | **not possible**. Use **HostProcess** containers (`windowsOptions.hostProcess: true`, needs `hostNetwork: true`) |
| **Identity** | UID/GID, can map to host | separate SAM: no host identities |
| **Memory over limit** | **OOM killer** terminates the process | **no OOM killer**: pagefiles are mandatory and no overcommit, so it pages to disk → slow, not killed |
| **CPU** | requests → weight, limits → quota | can **limit** CPU time, can't **guarantee** a minimum. kubelet flag `--windows-priorityclass` (≥ `ABOVE_NORMAL_PRIORITY_CLASS`) protects the kubelet |
| **Reservations** | `--kube-reserved` / `--system-reserved` lower allocatable **and** can be enforced via cgroups | **only lower allocatable** (nothing enforces them). Reserve **≥ 2GiB** memory |
| **Advice** | — | **always set limits**. Pods without them can over-provision a node until it's unhealthy |

---

## Lab 1 – What the API enforces for Windows Pods
```bash
cd concepts/configuration/windows-resource-management
kubectl create namespace winres-demo
kubectl apply -n winres-demo -f 01-windows-pods.yaml
#   win-privileged:            securityContext.privileged: Forbidden: cannot be set for a windows pod
#   win-hostprocess-nohostnet: spec.hostNetwork: Invalid value: false: hostNetwork must be true if pod contains any hostProcess containers
#   pod/win-hostprocess created          <- valid; Pending here (nodeSelector kubernetes.io/os: windows)
```

## Lab 2 – Reservations: minikube vs the page's advice
```bash
kubectl get node minikube -o jsonpath='capacity mem={.status.capacity.memory} allocatable mem={.status.allocatable.memory}{"\n"}'
#   capacity mem=31826084Ki allocatable mem=31826084Ki        <- identical: nothing reserved
kubectl get --raw /api/v1/nodes/minikube/proxy/configz | jq -c '.kubeletconfig | {kubeReserved, systemReserved, evictionHard, enforceNodeAllocatable}'
#   {"kubeReserved":null,"systemReserved":null,"evictionHard":{"imagefs.available":"0%","nodefs.available":"0%",...},"enforceNodeAllocatable":["pods"]}
minikube ssh -- "cat /sys/fs/cgroup/kubepods.slice/memory.max; free -b | awk '/Mem/{print \$2}'"
#   32589910016 / 32589910016                                  <- Pods may use ALL node memory
```
Fine for a laptop. On a Linux production node you'd set e.g. `kubeReserved: {cpu: 500m, memory: 1Gi}` + `systemReserved`, and the kubepods cgroup shrinks to match. On **Windows** the same settings only change the scheduler's arithmetic (allocatable), so limits on every Pod matter even more.

## Lab 3 – Memory pressure: Linux kills, Windows pages
On Linux, exceeding a limit is fatal (see `../manage-resources-containers`, Lab 3):
```
memory-hog: restarts=3 last=OOMKilled/137
```
The same container on Windows would keep running, but its working set would be paged to the mandatory pagefile, so everything on the node slows down. There's no `OOMKilled` signal to alert on. Watch memory and paging metrics instead (e.g. windows-exporter).

---

## Useful commands
```bash
kubectl get nodes -L kubernetes.io/os,node.kubernetes.io/windows-build
kubectl describe node <windows-node> | sed -n '/Capacity/,/System Info/p'
kubectl get --raw /api/v1/nodes/<n>/proxy/configz | jq '.kubeletconfig | {kubeReserved, systemReserved}'
```

## Cleanup
```bash
./cleanup.sh
```
