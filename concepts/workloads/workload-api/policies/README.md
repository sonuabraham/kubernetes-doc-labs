# PodGroup Scheduling Policies – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/workload-api/policies/

> Cluster: the `wl-lab` profile (`../start-wl-lab.sh`).

## Key ideas (read first)

| Policy | Meaning |
|---|---|
| **basic** | Each Pod is scheduled on its own, as in standard Kubernetes. The group is a label-like grouping (useful for observability and group-level features). |
| **gang** | **All-or-nothing**: the scheduler binds Pods only when at least `minCount` of the group can be placed **at the same time**. Otherwise none are bound, so no partial allocations hold resources. |
| **Composite gang** | On a CompositePodGroup: `minGroupCount` = how many **child groups** must be schedulable together (multi-level gang). |
| **Where it's set** | In a Workload's `podGroupTemplates[].schedulingPolicy` (copied into each PodGroup), or directly in a user-managed PodGroup. |

## The demo app
The docs snippets are **verbatim**: [policy-basic-snippet.yaml](policy-basic-snippet.yaml), [policy-gang-snippet.yaml](policy-gang-snippet.yaml) (`minCount: 4`) and [policy-composite-gang-snippet.yaml](policy-composite-gang-snippet.yaml) (`minGroupCount: 2`).
[01-manual-gang.yaml](01-manual-gang.yaml) has two user-managed PodGroups in `policy-demo`: `four-or-nothing` (gang, minCount 4) and `one-by-one` (basic). [add-member.sh](add-member.sh) `<group> <pod>` adds a Pod to a group.

---

## Lab 1 – basic vs gang, pod by pod
```bash
cd concepts/workloads/workload-api/policies
kubectl apply -f 01-manual-gang.yaml
for i in 1 2 3; do ./add-member.sh four-or-nothing g$i; done
./add-member.sh one-by-one b1 ; sleep 6
kubectl get pods -n policy-demo                 # b1 Running; g1 g2 g3 Pending
kubectl get podgroups -n policy-demo
#   four-or-nothing   Gang    Pending
#   one-by-one        Basic   Scheduled
./add-member.sh four-or-nothing g4 ; sleep 6
kubectl get pods -n policy-demo                 # g1..g4 Running - all four at once
kubectl get podgroups -n policy-demo            # four-or-nothing  Gang  Scheduled
```
The gang wasn't short of **resources**, it was short of **members**. The scheduler waits until `minCount` Pods exist and all fit.

## Lab 2 – Membership is permanent
```bash
kubectl patch pod g1 -n policy-demo -p '{"spec":{"schedulingGroup":{"podGroupName":"one-by-one"}}}'
#   Forbidden: pod updates may not change fields ...        <- spec.schedulingGroup is immutable
```

## Lab 3 – Gang through a Job and composite gangs
- Jobs: `../01-gang-vs-basic.yaml` and `../02-gang-fits.yaml` (parent README, Labs 2–3).
- Composite (`minGroupCount`): `../../compositepodgroup-api` (two child gangs of 4 must both be ready).

---

## Cleanup
```bash
kubectl delete namespace policy-demo
```
