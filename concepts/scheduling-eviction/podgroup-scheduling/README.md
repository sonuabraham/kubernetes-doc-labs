# PodGroup Scheduling – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/podgroup-scheduling/

> No YAML on the page. Runs on **`wl-lab`** with 4 fake nodes (`CTX=wl-lab ../fake-nodes.sh up 4`). Each Pod asks for 3 CPU, which is one slot per fake node. [interleave.sh](interleave.sh) creates two competing 3-Pod "jobs", alternating their Pods, with or without PodGroups ([00-groups.yaml](00-groups.yaml)).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Problem** | Pod-by-Pod scheduling of competing multi-Pod workloads can **deadlock**: each gets part of the capacity, and none can run. |
| **PodGroup scheduling cycle** | A PodGroup enters the queue (once the PodGroup and ≥1 Pod are seen). When popped, **all** its unscheduled Pods are evaluated against **one snapshot**: sorted by priority, then arrival. |
| **Default algorithm** | Per Pod: normal Filter/Score, then the Pod is *assumed* on its node. After each Pod, `PlacementFeasible` checks the group criteria (`minCount`). |
| **Atomic outcome** | Feasible → those Pods go straight to binding (the rest are requeued immediately). Infeasible → nothing binds, and `PodGroupPostFilter` (workload-aware preemption, see `../workload-aware-preemption`) may free space for the next try. |
| **Placement algorithm** (`TopologyAwareWorkloadScheduling`, alpha) | Generate candidate node subsets (e.g. per zone/rack), run the default algorithm in each, score the feasible placements, and pick the best (see `../topology-aware-scheduling`). |
| **Conditions** | PodGroup `PodGroupInitiallyScheduled` (set once, when the group first meets its policy). CompositePodGroup has its own. |

---

## Step 1
```bash
cd concepts/scheduling-eviction/podgroup-scheduling
CTX=wl-lab ../fake-nodes.sh up 4 ; kubectl config use-context wl-lab
kubectl apply -f 00-groups.yaml           # namespace pg-sched, gang PodGroups job-a, job-b (minCount 3)
```

## Lab 1 – Pod-by-Pod: deadlock
```bash
./interleave.sh plain
kubectl get pods -n pg-sched -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName
#   plain-a-1 fake-3   plain-a-2 fake-2   plain-a-3 <none>
#   plain-b-1 fake-4   plain-b-2 fake-1   plain-b-3 <none>        <- 4 slots used, NEITHER job has all 3 Pods
```

## Lab 2 – PodGroup cycle: one wins, the other waits
```bash
kubectl delete pods -n pg-sched --all --grace-period=0 --force
./interleave.sh grouped
#   a-1 fake-3   a-2 fake-1   a-3 fake-4              <- job-a placed as a unit
#   b-1 <none>   b-2 <none>   b-3 <none>              <- job-b holds NOTHING (no wasted slot)
kubectl get podgroups -n pg-sched                     # job-a Scheduled, job-b Unschedulable
kubectl delete pods -n pg-sched -l job=a --grace-period=0 --force     # job-a "finishes"
#   ~10s later: b-1 fake-3   b-2 fake-1   b-3 fake-2
kubectl get podgroup job-a job-b -n pg-sched -o jsonpath='{range .items[*]}{.metadata.name}: {.status.conditions[0].type}={.status.conditions[0].reason} {.status.conditions[0].lastTransitionTime}{"\n"}{end}'
#   job-a: PodGroupInitiallyScheduled=Scheduled 04:05:57
#   job-b: PodGroupInitiallyScheduled=Scheduled 04:06:07
```
Same Pods, same arrival order. Only the grouping changed, and it turned a permanent deadlock into a queue.

---

## Useful commands
```bash
kubectl get podgroups -n pg-sched -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].reason
kubectl get events -n pg-sched --field-selector reason=FailedScheduling -o custom-columns=OBJ:.involvedObject.name,M:.message
```

## Cleanup
```bash
./cleanup.sh            # (wl-lab context)
```
