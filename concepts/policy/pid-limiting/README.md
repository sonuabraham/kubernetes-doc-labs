# Process ID Limits And Reservations – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/policy/pid-limiting/

> PID limits are **kubelet settings**, not Pod fields, so the lab uses a separate profile **`pid-lab`** ([start-pid-lab.sh](start-pid-lab.sh): `--pod-max-pids=64`, `--system-reserved=pid=1000`) and leaves the main cluster alone. [01-fork-bomb.yaml](01-fork-bomb.yaml) forks until it can't.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Why** | PIDs are finite per node (`/proc/sys/kernel/pid_max`). A fork bomb can exhaust them without hitting CPU/memory limits and take down kubelet, runtime and sshd. |
| **Pod PID limit** | kubelet `--pod-max-pids` / `podPidsLimit` → the Pod's cgroup `pids.max`. **Same for every Pod on that node**: no per-Pod field. Keep nodes uniform. |
| **Node PID reservation** | `--system-reserved=pid=N` / `--kube-reserved=pid=N` keep PIDs for the OS and daemons (like CPU/memory reservations). |
| **PID-based eviction** | `evictionHard: {pid.available: "10%"}` → node condition `PIDPressure`, Pods evicted. |
| **Defaults** | `podPidsLimit: -1` = unlimited (only the runtime's own limits apply). |

---

## Lab 1 – The main cluster: no Pod PID limit
```bash
kubectl get --raw /api/v1/nodes/minikube/proxy/configz | jq -c '.kubeletconfig | {podPidsLimit, systemReserved, kubeReserved}'
#   {"podPidsLimit":-1,"systemReserved":null,"kubeReserved":null}
minikube ssh -- "cat /proc/sys/kernel/pid_max"        # 4194304
kubectl get node minikube -o jsonpath='{.status.conditions[?(@.type=="PIDPressure")].message}'    # kubelet has sufficient PID available
```

## Lab 2 – Turn it on and fork
```bash
cd concepts/policy/pid-limiting
./start-pid-lab.sh
kubectl --context pid-lab get --raw /api/v1/nodes/pid-lab/proxy/configz | jq -c '.kubeletconfig | {podPidsLimit, systemReserved}'
#   {"podPidsLimit":64,"systemReserved":{"pid":"1000"}}
kubectl --context pid-lab apply -f 01-fork-bomb.yaml
kubectl --context pid-lab logs forker
#   fork #63 failed: [Errno 11] Resource temporarily unavailable
#   started 62 child processes
#   pids.max 5586 pids.current 63            <- the CONTAINER cgroup's own (runtime) limit; not the binding one
U=$(kubectl --context pid-lab get pod forker -o jsonpath='{.metadata.uid}' | tr - _)
minikube -p pid-lab ssh -- "cat /sys/fs/cgroup/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-pod$U.slice/pids.max"
#   64                                        <- the POD cgroup: python + 62 children + the pause container = 64
kubectl --context pid-lab exec neighbour -- sh -c 'sleep 1 & echo neighbour can still fork'    # unaffected
```
The fork bomb is contained to its own Pod: it gets `EAGAIN`, and the node and its neighbours carry on. A careless shell script (busybox `sh`) simply **exits** on the first failed fork. That's what happened in our first attempt, which is why the demo uses Python.

```bash
minikube stop -p pid-lab ; kubectl config use-context minikube
```

---

## Useful commands
```bash
kubectl get --raw /api/v1/nodes/<n>/proxy/configz | jq '.kubeletconfig | {podPidsLimit, systemReserved, kubeReserved, evictionHard}'
kubectl get nodes -o custom-columns=NAME:.metadata.name,PIDPRESSURE:'.status.conditions[?(@.type=="PIDPressure")].status'
kubectl exec <pod> -- cat /sys/fs/cgroup/pids.current
```

## Cleanup
```bash
./cleanup.sh       # stops pid-lab (minikube delete -p pid-lab to remove it)
```
