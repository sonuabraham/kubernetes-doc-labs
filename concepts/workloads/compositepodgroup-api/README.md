# CompositePodGroup API – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/compositepodgroup-api/

> Sub-page: [lifecycle](lifecycle/). Cluster: the `wl-lab` profile (`../workload-api/start-wl-lab.sh`), with `CompositePodGroup` (alpha) and `scheduling.k8s.io/v1alpha3` on.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **CompositePodGroup** | `scheduling.k8s.io/v1alpha3`. A **non-leaf** node in a group hierarchy. It holds no Pods itself. Its children are PodGroups (leaves) or other CompositePodGroups. |
| **Multi-level gang** | `schedulingPolicy.gang.minGroupCount`: how many **child groups** must be schedulable together. Each child still has its own `minCount`. |
| **Links** | Children point up with `spec.parentCompositePodGroupName`. All of them point to their template with `spec.workloadRef` (`workloadName`, `templateName`). |
| **Status** | Reflects the whole subtree's placement. |
| **Use case** | For example training with two worker sets that are useless unless **both** can start. |

## The demo app
The docs examples are **verbatim**: [hierarchical-workload.yaml](hierarchical-workload.yaml) (Workload `hierarchical-workload` → CompositePodGroup `root-group-0` (gang `minGroupCount: 2`) → PodGroups `workers-a-0`, `workers-b-0` (gang `minCount: 4` each) → Pod `worker-a-0`), [compositepodgroup-root.yaml](compositepodgroup-root.yaml), and the snippets `spec-*-snippet.yaml`.

---

## Lab 1 – Build the hierarchy (docs example)
```bash
cd concepts/workloads/compositepodgroup-api
kubectl apply -f hierarchical-workload.yaml
kubectl get workloads,compositepodgroups,podgroups
#   compositepodgroup root-group-0   Gang   hierarchical-workload
#   podgroup workers-a-0 / workers-b-0   Gang   Pending
kubectl get pod worker-a-0          # Pending
```

## Lab 2 – Multi-level all-or-nothing
```bash
mem(){ kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $1}
spec:
  schedulingGroup: {podGroupName: $2}
  containers: [{name: c, image: registry.k8s.io/pause:3.10}]
YAML
}
for i in 1 2 3; do mem worker-a-$i workers-a-0; done ; sleep 5
kubectl get pods | grep worker-a          # worker-a-0..3 Pending - group A is complete (4/4) but group B is empty
kubectl get podgroups                     # workers-a-0 Pending
for i in 0 1 2 3; do mem worker-b-$i workers-b-0; done ; sleep 8
kubectl get pods | grep -E 'worker-(a|b)' # all 8 Running together
kubectl get podgroups                     # workers-a-0 Scheduled, workers-b-0 Scheduled
```
Group A alone satisfied **its** gang (4 pods) and still didn't start: the **root** demanded 2 schedulable child groups (`minGroupCount: 2`).

---

## Useful commands
```bash
kubectl get compositepodgroups,podgroups
kubectl get podgroups -o custom-columns=NAME:.metadata.name,PARENT:.spec.parentCompositePodGroupName,STATUS:.status.conditions[0].reason
```

## Cleanup
```bash
kubectl delete pod worker-a-0 worker-a-1 worker-a-2 worker-a-3 worker-b-0 worker-b-1 worker-b-2 worker-b-3 --ignore-not-found
kubectl delete -f hierarchical-workload.yaml --ignore-not-found
```
