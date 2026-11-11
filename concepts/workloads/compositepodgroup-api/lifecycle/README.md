# CompositePodGroup Lifecycle – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/compositepodgroup-api/lifecycle/

> Cluster: the `wl-lab` profile. Uses the hierarchy from [../](../) (`hierarchical-workload.yaml`).

## Key ideas (read first)

| Rule | Meaning |
|---|---|
| **Ownership / GC** | The whole tree (CompositePodGroups + PodGroups) is owned by the workload controller's object and garbage-collected with it. |
| **Top-down creation** | Workload → root CompositePodGroup (`workloadRef` → root template) → descendants (`parentCompositePodGroupName` + `workloadRef`) → Pods. Missing parents mean the scheduler **holds off** until the tree exists. |
| **Consistency across the tree** | Same `schedulerName`, same `priority` (= the root group's), same `preemptionPolicy` for **all** Pods in the hierarchy. |
| **Limits** | Depth ≤ 4, ≤ 8 child templates per level. |
| **Immutable** | `gang.minGroupCount`, `parentCompositePodGroupName`, the Pods' `schedulingGroup`. |

---

## Lab 1 – minGroupCount can't change
```bash
kubectl apply -f ../hierarchical-workload.yaml
kubectl patch compositepodgroup root-group-0 --type=merge -p '{"spec":{"schedulingPolicy":{"gang":{"minGroupCount":1}}}}'
#   The CompositePodGroup "root-group-0" is invalid: spec.schedulingPolicy: Invalid value: null: field is immutable
```

## Lab 2 – A child needs its template reference
```bash
kubectl apply -f - <<'YAML'
apiVersion: scheduling.k8s.io/v1beta1
kind: PodGroup
metadata: {name: lost-child}
spec:
  parentCompositePodGroupName: no-such-parent
  schedulingPolicy: {basic: {}}
YAML
#   spec.workloadRef: Required value: must be set when parentCompositePodGroupName is set
```
Children of a composite group must always say which Workload template they come from.

## Lab 3 – Garbage collection with an owner
User-created trees (as in the docs example) have **no** owner, so you delete them yourself. A controller (JobSet, for example) would set `ownerReferences` on the root and its descendants, so deleting the JobSet removes the tree. Simulate it:
```bash
UID_=$(kubectl get workload hierarchical-workload -o jsonpath='{.metadata.uid}')
for o in compositepodgroup/root-group-0 podgroup/workers-a-0 podgroup/workers-b-0; do
  kubectl patch $o --type=merge -p "{\"metadata\":{\"ownerReferences\":[{\"apiVersion\":\"scheduling.k8s.io/v1alpha3\",\"kind\":\"Workload\",\"name\":\"hierarchical-workload\",\"uid\":\"$UID_\"}]}}"; done
kubectl delete pods --all ; kubectl delete workload hierarchical-workload ; sleep 5
kubectl get compositepodgroups,podgroups          # the whole hierarchy is gone
```

---

## Cleanup
```bash
kubectl delete -f ../hierarchical-workload.yaml --ignore-not-found
```
