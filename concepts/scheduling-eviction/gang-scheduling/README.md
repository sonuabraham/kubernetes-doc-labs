# Gang Scheduling – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/gang-scheduling/

> No YAML on the page. **Needs the gated APIs** (`GenericWorkload`, `CompositePodGroup`, `scheduling.k8s.io/v1beta1` + `v1alpha3`): run on the **`wl-lab`** profile (`../../workloads/workload-api/start-wl-lab.sh`) with fake nodes there (`CTX=wl-lab ../fake-nodes.sh up 4`, 4 CPU each). Every Pod asks for **3 CPU** and `nodeSelector type=fake`, so there's exactly **one slot per fake node**. [pods.sh](pods.sh) `<group> <from> <to>` creates group members. The APIs themselves: `../../workloads/podgroup-api`, `../../workloads/compositepodgroup-api`.

## Key ideas (read first)

| Step (GangScheduling plugin) | What happens |
|---|---|
| **PreEnqueue** | Pods wait **outside** the scheduling queue until the PodGroup exists **and** at least `minCount` member Pods exist. |
| **PodGroup cycle** | One atomic decision for all unscheduled members (see `../podgroup-scheduling`). `PlacementFeasible` counts placed + already scheduled Pods against `minCount`. |
| **Bind** | ≥ `minCount` placements → those Pods bind (extras beyond the slots stay Pending). Fewer → **none** bind, all go to the unschedulable queue. |
| **Below minCount later** | Scheduled Pods aren't evicted. New ones are placed only if scheduled + newly feasible ≥ `minCount`. |
| **CompositePodGroup** (alpha) | Gangs of gangs: `gang.minGroupCount` child groups must fit together, or none. A hierarchical quorum is checked bottom-up in PreEnqueue. `basic` lets children schedule independently. |

---

## Step 1
```bash
cd concepts/workloads/workload-api && ./start-wl-lab.sh && cd ../../scheduling-eviction
CTX=wl-lab ./fake-nodes.sh up 4 ; cd gang-scheduling
kubectl apply -f 00-podgroups.yaml        # PodGroups quorum (minCount 4), too-big (5), partial (4) in gang-sched
```

## Lab 1 – Quorum (PreEnqueue)
```bash
./pods.sh quorum 1 3
kubectl get pod quorum-1 -n gang-sched -o jsonpath='{.status.conditions}'    # (empty) - no PodScheduled condition, no events
./pods.sh quorum 4 4
#   quorum-1=fake-1 quorum-2=fake-3 quorum-3=fake-2 quorum-4=fake-4      <- all four at once, as soon as the 4th exists
kubectl get podgroup quorum -n gang-sched -o jsonpath='{.status.conditions[*].type}={.status.conditions[*].reason}'
#   PodGroupInitiallyScheduled=Scheduled
```
Three Pods weren't "Unschedulable", they simply never entered the queue.

## Lab 2 – More Pods than minCount
```bash
./pods.sh partial 1 6           # minCount 4, 4 slots
#   partial-1..4 bound (fake-1, fake-2, fake-4, fake-3)   partial-5, partial-6 Pending ("4 Insufficient cpu")
```
`minCount` is a floor, not a size: once it's satisfied, whatever fits binds.

## Lab 3 – minCount that can't be met
```bash
./pods.sh too-big 1 5           # minCount 5, 4 slots (on otherwise empty fake nodes)
#   all 5 Pending
#   "pod group is unschedulable ... 0/1 placements are available, first placement status: minCount (5) cannot be satisfied:
#    4 scheduled, 0 remaining, pod group preemption: No preemption victims found for incoming preemptor"
```
Nothing is bound, so no capacity is wasted on a group that can't run.

## Lab 4 – Dropping below minCount
```bash
# partial: delete one bound Pod → partial-5 is placed (3 scheduled + 1 feasible = 4 ≥ minCount)
# delete more until only partial-4, partial-5 are left (2 scheduled), then:
./pods.sh partial 7 7           # partial-7 Pending - 2 + 1 < 4: held back, no event
./pods.sh partial 8 8           # partial-7 → fake-2, partial-8 → fake-4: 2 + 2 = 4, both placed together
```

## Lab 5 – Gang of gangs (CompositePodGroup)
```bash
kubectl delete pods -n gang-sched --all --grace-period=0 --force
kubectl apply -f 01-composite.yaml        # Workload + CompositePodGroup root (minGroupCount 2) → PodGroups a (minCount 2), b (minCount 3)
./pods.sh a 1 2 ; ./pods.sh b 1 3          # 5 Pods, 4 slots
#   a-1/a-2 <none>   b-1..3 <none>          <- "a" alone would fit, but root needs BOTH children
CTX=wl-lab ../fake-nodes.sh up 5           # a 5th slot
#   a-1=fake-3 a-2=fake-5   b-1=fake-1 b-2=fake-4 b-3=fake-2     <- all five together
```
Unlike plain PodGroups, composite hierarchies are rejected without a `workloadRef`: *"spec.workloadRef: Required value: must be set when parentCompositePodGroupName is set"*.

---

## Useful commands
```bash
kubectl get podgroups,compositepodgroups -n gang-sched
kubectl get pods -n gang-sched -o custom-columns=NAME:.metadata.name,GROUP:.spec.schedulingGroup.podGroupName,NODE:.spec.nodeName
kubectl get events -n gang-sched --field-selector reason=FailedScheduling
```

## Cleanup
```bash
./cleanup.sh            # (wl-lab context) - see ../README.md for stopping wl-lab and the fake nodes
```
