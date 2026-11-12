# Pod-level Resource Managers – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/resource-management/pod-level-resource-managers/

> No YAML on the page. Builds on the **`rm-lab`** profile from [../resource-managers](../resource-managers/) (CPU manager `static` with CPU 0 reserved, memory manager `Static`). [set-kubelet.sh](set-kubelet.sh) turns on **`PodLevelResourceManagers`** (beta, **off** by default) in that kubelet and sets the Topology Manager **scope**. [01-hybrid-pod.yaml](01-hybrid-pod.yaml) has a pod-level budget of 4 CPU / 1Gi, a Guaranteed `worker` (2 CPU) and a `sidecar` with no resources.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Before** | Exclusive, NUMA-aligned resources only if **every** container is Guaranteed. |
| **With pod-level managers** | The managers use `spec.resources` (pod-level, needs `PodLevelResources`) as the allocation basis. |
| **Exclusive slice** | A **Guaranteed container** (requests = limits, integer CPU) gets dedicated CPUs/memory. |
| **`pod` scope** | One NUMA-aligned **Pod bubble** sized by `spec.resources`. Exclusive slices are carved out of it, and the remaining containers share the rest: a **pod shared pool**, isolated from other Pods. |
| **`container` scope** | **Hybrid**: Guaranteed containers get exclusive resources from the node, the others run in the **node** shared pool, and `spec.resources` caps the Pod as a whole (CFS quota). |
| **Lifecycle** | Init containers' slices are reusable, sidecars' persist. State is checkpointed. Kubelet downgrades need care. |
| **Observability** | PodResources API reports the allocations per container. |

---

## Step 1
```bash
cd concepts/resource-management/pod-level-resource-managers
# rm-lab must exist: ../resource-managers/start-rm-lab.sh
./set-kubelet.sh pod
#   {"featureGates":{"PodLevelResourceManagers":true},"topologyManagerScope":"pod","cpuManagerPolicy":"static","memoryManagerPolicy":"Static"}
kubectl --context rm-lab create ns plrm-demo
```
The script deletes the CPU/memory manager checkpoint files before restarting the kubelet: it refuses to start if the scope or policy changed under existing state (on a real node you drain it first). This host prints *"Failed to allocate directory watch: Too many open files"* (inotify limit), but the kubelet comes up fine.

## Lab 1 – `pod` scope: a Pod bubble with an internal shared pool
```bash
kubectl --context rm-lab apply -n plrm-demo -f 01-hybrid-pod.yaml
for c in worker sidecar; do kubectl --context rm-lab exec -n plrm-demo hybrid -c $c -- grep Cpus_allowed_list /proc/self/status; done
#   worker:  1-2          <- exclusive slice
#   sidecar: 3-4          <- the Pod's own shared pool (bubble = 1-4), NOT the node pool
kubectl --context rm-lab run other -n plrm-demo --image=busybox:1.36 -- sleep 3600
kubectl --context rm-lab exec -n plrm-demo other -- grep Cpus_allowed_list /proc/self/status
#   0,5-7                 <- other Pods can't touch CPUs 1-4
minikube -p rm-lab ssh -- "sudo cat /var/lib/kubelet/cpu_manager_state" | jq -c '{defaultCpuSet, entries}'
#   {"defaultCpuSet":"0,5-7","entries":{"<uid>":{"sidecar":"3-4","worker":"1-2"}}}
```
`sidecar` has no requests at all, yet it got dedicated CPUs because the **Pod** is Guaranteed at the pod level.

## Lab 2 – `container` scope: hybrid
```bash
kubectl --context rm-lab delete pod hybrid other -n plrm-demo
./set-kubelet.sh container
kubectl --context rm-lab apply -n plrm-demo -f 01-hybrid-pod.yaml
#   worker:  1-2          <- still exclusive
#   sidecar: 0,3-7        <- node shared pool
U=$(kubectl --context rm-lab get pod hybrid -n plrm-demo -o jsonpath='{.metadata.uid}' | tr - _)
minikube -p rm-lab ssh -- "cat /sys/fs/cgroup/kubepods.slice/kubepods-pod$U.slice/cpu.max /sys/fs/cgroup/kubepods.slice/kubepods-pod$U.slice/memory.max"
#   400000 100000 / 1073741824           <- spec.resources still caps the whole Pod at 4 CPU / 1Gi
```

---

## Useful commands
```bash
kubectl exec <pod> -c <container> -- grep Cpus_allowed_list /proc/self/status
minikube -p rm-lab ssh -- "sudo cat /var/lib/kubelet/cpu_manager_state"
kubectl get --raw /api/v1/nodes/rm-lab/proxy/configz | jq '.kubeletconfig | {featureGates, topologyManagerScope}'
```

## Cleanup
```bash
./cleanup.sh       # namespace, stops rm-lab, back to the minikube context
```
