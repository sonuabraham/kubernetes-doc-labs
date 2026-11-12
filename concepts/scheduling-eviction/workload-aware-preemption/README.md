# Workload-Aware Preemption – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/workload-aware-preemption/

> No YAML on the page. Runs on **`wl-lab`** with 4 fake nodes (`CTX=wl-lab ../fake-nodes.sh up 4`), with one 3-CPU Pod per node. [run-case.sh](run-case.sh) fills the cluster with low-priority work, submits a **2-Pod high-priority gang** (`disruptionMode: all`), and lists the victims. PodGroup priority and disruption modes are explained in `../../workloads/workload-api/disruption-and-priority`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Preemptor = PodGroup** | When a PodGroup can't be scheduled, `PodGroupPostFilter` (DefaultPreemption) treats the whole group as **one preemptor**. It replaces per-Pod preemption for group members. (The v1.36 `WorkloadAwarePreemption` gate was merged into `GenericWorkload`.) |
| **Cluster-wide domain** | Victims are chosen across **all nodes at once**, not node by node. |
| **Preemption units** | Single Pods, or PodGroups. With `disruptionMode: all` the whole group goes (a partial gang is useless). With `single`, members can be taken individually. |
| **Importance order** (spared first) | higher **priority** > **PodGroup over single Pod** (same priority) > **larger group** > **earlier start**. |
| **Reprieval** | Simulate removing all candidate victims, find a placement, then **give back** as many victims as possible, least important last. Fast, not necessarily optimal. |
| **CompositePodGroups** | The same, applied to the hierarchy. |

---

## Step 1
```bash
cd concepts/scheduling-eviction/workload-aware-preemption
kubectl config use-context wl-lab ; CTX=wl-lab ../fake-nodes.sh up 4
kubectl apply -f 00-setup.yaml            # namespace wap, PriorityClasses wap-low (10), wap-high (1000)
```

## Lab – Three victim sets for the same preemptor
```bash
for c in single all mixed; do echo "## $c"; ./run-case.sh $c; done
```
Measured:
```
## single   (low gang of 4, disruptionMode single)
before: low-1=fake-3 low-2=fake-2 low-3=fake-1 low-4=fake-4
victims: low-1 low-2                                   <- only the 2 Pods actually needed; the other 2 were reprieved
high-1/high-2 nominated fake-3/fake-2
event: "Preempted by podgroup 1c42… on node cluster"   <- the cluster is the preemption domain

## all      (low gang of 4, disruptionMode all)
victims: low-1 low-2 low-3 low-4                       <- the whole unit, though 2 slots would have been enough

## mixed    (2 standalone low Pods + low gang of 2, same priority 10)
before: lone-1=fake-3 lone-2=fake-2 low-1=fake-1 low-2=fake-4
victims: lone-1 lone-2                                 <- single Pods are less important than a PodGroup at equal priority
```
Victims stay `Terminating` on fake nodes (no kubelet). `run-case.sh` force-deletes everything before each case. Events accumulate in the namespace, so the counts grow across cases.

---

## Useful commands
```bash
kubectl get pods -n wap -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,NOMINATED:.status.nominatedNodeName,DELETING:.metadata.deletionTimestamp
kubectl get events -n wap --field-selector reason=Preempted
kubectl get podgroups -n wap -o custom-columns=NAME:.metadata.name,PRIO:.spec.priority,DISRUPTION:.spec.disruptionMode
```

## Cleanup
```bash
./cleanup.sh            # (wl-lab context)
```
