# Topology-Aware Scheduling – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-aware-scheduling/

> The docs' scheduler config is **verbatim** in [kubeschedulerconfig-tas-weights.yaml](kubeschedulerconfig-tas-weights.yaml) (placement-score weights; reference). Runs on **`wl-lab`** (`TopologyAwareWorkloadScheduling` on) with **6 fake nodes in 3 zones** (`CTX=wl-lab ../fake-nodes.sh up 6`: fake-1/4 zone-a, fake-2/5 zone-b, fake-3/6 zone-c). [fill.sh](fill.sh) pre-loads the zones. Every worker Pod asks for 2 CPU. The PodGroup object side (`schedulingConstraints.topology`) is in `../../workloads/workload-api/topology-aware-scheduling`.

## Key ideas (read first)

| Plugin / phase | Role |
|---|---|
| **TAS** | A *placement* algorithm for PodGroups: **all Pods of the group in one topology domain** (the `topology[].key` in the PodGroup's `schedulingConstraints`). |
| **TopologyPlacement** (PlacementGenerate) | One candidate placement per distinct value of the key (here: per zone). |
| **Feasibility** | The default PodGroup algorithm runs inside each candidate. Infeasible candidates are dropped. |
| **NodeResourcesFit** (PlacementScore) | Bin-packs placements: always **MostAllocated** across the placement's nodes (uses your resource weights). |
| **PodGroupPodsCount** (PlacementScore) | Prefers placements that fit more of the group's Pods. Default weights: both 1. |
| **Multi-level** (`CompositePodGroup`) | Top-down subdivision: the root picks e.g. a zone, children pick racks inside it. |

---

## Step 1
```bash
cd concepts/scheduling-eviction/topology-aware-scheduling
kubectl config use-context wl-lab ; CTX=wl-lab ../fake-nodes.sh up 6
kubectl apply -f 00-setup.yaml ; ./fill.sh
#   zone-a: fake-1 full (3 CPU filler)   zone-b: empty   zone-c: fake-3, fake-6 with 500m each
```
Each fake node also runs a **kindnet** DaemonSet Pod (100m), so only **one** 2-CPU worker fits per node, i.e. 2 per zone.

## Lab 1 – Same two Pods, with and without a zone constraint
```bash
# no PodGroup:                    free-1=fake-5  free-2=fake-2        <- pod-by-pod LeastAllocated: emptiest nodes (zone-b)
# PodGroup "train" (gang 2, topology key zone):
#                                 tas-1=fake-6   tas-2=fake-3          <- zone-c: candidates b and c both fit;
#                                                                         placement scoring is MostAllocated → the fuller zone wins
```

## Lab 2 – A gang that fits the cluster but no single zone
```bash
# PodGroup "train3" (gang 3, topology key zone):
#   t3-1..3 Pending
#   "pod group is unschedulable ... 0/3 placements are available, first placement status:
#    minCount (3) cannot be satisfied: 1 scheduled, 1 remaining ..."
# PodGroup "train3-anywhere" (gang 3, NO topology):
#   any-1=fake-5(zone-b) any-2=fake-2(zone-b) any-3=fake-4(zone-a)      <- placed across zones
```
"0/3 placements": one candidate per zone, none can hold 3 Pods. The topology constraint turned free capacity into an unschedulable gang. That's the price of co-location, and why you size gangs to your topology domains.

## Lab 3 – Tuning (docs config)
[kubeschedulerconfig-tas-weights.yaml](kubeschedulerconfig-tas-weights.yaml) raises `PodGroupPodsCount` (5) over `NodeResourcesFit` (2) at the **placementScore** extension point, and changes cpu/memory weights for both pod-by-pod and placement scoring. It's applied as `--config` of a scheduler, the same way as in `../scheduling-framework` and `../resource-bin-packing`.

---

## Useful commands
```bash
kubectl get pods -n tas -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
kubectl get nodes -l type=fake -L topology.kubernetes.io/zone
kubectl get podgroup <g> -n tas -o jsonpath='{.spec.schedulingConstraints}'
```

## Cleanup
```bash
./cleanup.sh            # (wl-lab context); then see ../README.md to stop the fake nodes and wl-lab
```
