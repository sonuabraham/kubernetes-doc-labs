# Pod Quality of Service Classes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/

## Key ideas (read first)

| Class | Criteria | Under node pressure |
|---|---|---|
| **Guaranteed** | **Every** container has CPU **and** memory requests **= limits** (requests default to limits if only limits are set). Or, with **pod-level resources**: pod-level CPU and memory requests = limits. | Evicted **last**. Killed only if it exceeds its limits. |
| **Burstable** | Not Guaranteed, but at least one container (or the pod level) has a CPU or memory request or limit. | After BestEffort. |
| **BestEffort** | No requests or limits anywhere. | Evicted **first**. |

| Concept | Meaning |
|---|---|
| **Set by Kubernetes** | `status.qosClass` is computed, not chosen, and is immutable for the Pod's life. |
| **Eviction order** | BestEffort → Burstable → Guaranteed. With resource pressure, only Pods **above their requests** are candidates. |
| **OOM score** | The kubelet sets `oom_score_adj` by class: Guaranteed **-997**, BestEffort **1000**, Burstable in between (1000 − 1000×memRequest/nodeMemory, clamped to 2…999). |
| **cgroups** | `kubepods.slice/kubepods-besteffort.slice`, `kubepods-burstable.slice`, and Guaranteed pods directly under `kubepods.slice`. |
| **Memory QoS (cgroup v2)** | `MemoryQoS` (beta) uses `memory.min` / `memory.high` = requests + `memoryThrottlingFactor` × (limits − requests), configured in the kubelet (`memoryThrottlingFactor`, `memoryReservationPolicy`). |
| **Class-independent** | Any container over its memory limit is OOM-killed, and CPU limits throttle, whatever the class. |

## The demo app
[00-qos-pods.yaml](00-qos-pods.yaml) creates namespace `qos-demo` with six pods: `guaranteed`, `guaranteed-limits-only`, `burstable`, `burstable-mixed`, `besteffort`, `guaranteed-pod-level`. [kubelet-memoryqos-excerpt.yaml](kubelet-memoryqos-excerpt.yaml) is the docs' KubeletConfiguration snippet, **verbatim**.

---

## Lab 1 – Which class did each pod get?
```bash
cd concepts/workloads/pods/pod-qos
kubectl apply -f 00-qos-pods.yaml ; sleep 12
kubectl get pods -n qos-demo -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
```
Expected:
```
besteffort               BestEffort
burstable                Burstable    <- memory request 32Mi != limit 128Mi
burstable-mixed          Burstable    <- one strict container + one with nothing = Burstable
guaranteed               Guaranteed
guaranteed-limits-only   Guaranteed   <- only limits set -> requests copied from limits
guaranteed-pod-level     Guaranteed   <- pod-level requests == limits (PodLevelResources, beta)
```
```bash
kubectl get pod guaranteed-limits-only -n qos-demo -o jsonpath='{.spec.containers[0].resources}{"\n"}'   # requests filled in = limits
```

## Lab 2 – What the class changes on the node
```bash
for p in guaranteed burstable besteffort guaranteed-pod-level; do
  c=$(kubectl get pod $p -n qos-demo -o jsonpath='{.spec.containers[0].name}')
  printf '%-22s oom_score_adj=%-5s memory.max=%s\n' $p "$(kubectl exec $p -n qos-demo -c $c -- cat /proc/1/oom_score_adj)" "$(kubectl exec $p -n qos-demo -c $c -- cat /sys/fs/cgroup/memory.max)"; done
```
Expected:
```
guaranteed             oom_score_adj=-997  memory.max=67108864    <- almost never chosen by the OOM killer
burstable              oom_score_adj=999   memory.max=134217728   <- tiny request on a 30 GiB node -> close to 1000
besteffort             oom_score_adj=1000  memory.max=max         <- first in line, no limit at all
guaranteed-pod-level   oom_score_adj=-997  memory.max=100663296   <- containers inherit the 96Mi POD limit
```
The cgroup tree is grouped by class:
```bash
minikube ssh -- "ls -d /sys/fs/cgroup/kubepods.slice/*/"
#   kubepods-besteffort.slice/  kubepods-burstable.slice/  kubepods-pod<uid>.slice/ (one per Guaranteed pod)
U=$(kubectl get pod guaranteed-pod-level -n qos-demo -o jsonpath='{.metadata.uid}' | tr - _)
minikube ssh -- "cat /sys/fs/cgroup/kubepods.slice/kubepods-pod$U.slice/memory.max /sys/fs/cgroup/kubepods.slice/kubepods-pod$U.slice/cpu.max"
#   100663296   30000 100000      <- the POD-level limit is enforced on the pod cgroup
```

## Lab 3 – Memory QoS (cgroup v2)
```bash
kubectl get --raw /api/v1/nodes/minikube/proxy/metrics | grep 'feature_enabled{name="MemoryQoS"'   # BETA ... 1 (on in the kubelet)
kubectl exec burstable -n qos-demo -- cat /sys/fs/cgroup/memory.high                               # max
minikube ssh -- "sudo grep -E 'memoryThrottlingFactor|memoryReservationPolicy' /var/lib/kubelet/config.yaml"   # (none)
```
Per the docs formula, the burstable pod would get `memory.high = 32Mi + 0.9 × (128Mi − 32Mi) ≈ 118Mi`. On this minikube the gate is on, but **`memory.high` stays `max`**, and the kubelet config has neither setting from [kubelet-memoryqos-excerpt.yaml](kubelet-memoryqos-excerpt.yaml). To experiment, add those two lines to `/var/lib/kubelet/config.yaml`, restart the kubelet (`sudo systemctl restart kubelet`), recreate the pod and re-check. Treat this as an exploration, not a guaranteed result.

## Lab 4 – Eviction order (reasoning)
Node-pressure eviction would pick `besteffort` first, then Burstable pods using more than their requests. A Guaranteed pod is only at risk once it exceeds its own limits. Seeing it live needs real memory pressure on the node. See `../../../scheduling-eviction/node-pressure-eviction`.

---

## Useful commands
```bash
kubectl get pods -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
kubectl describe pod <p> | grep 'QoS Class'
kubectl exec <p> -- cat /proc/1/oom_score_adj
```

## Cleanup
```bash
./cleanup.sh
```
