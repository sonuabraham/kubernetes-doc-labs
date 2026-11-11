# PodGroup Lifecycle – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/podgroup-api/lifecycle/

> Cluster: the `wl-lab` profile (`../../workload-api/start-wl-lab.sh`).

## Key ideas (read first)

| Rule | Meaning |
|---|---|
| **Ownership** | Controller-made PodGroups are owned by the controller's object (Job → `ownerReferences`) and garbage-collected with it. |
| **Creation order** | Workload → PodGroup → Pods. A Pod pointing to a PodGroup that doesn't exist **waits** (no event), and is queued once it appears. |
| **Deletion protection** | Finalizer **`scheduling.k8s.io/podgroup-protection`**: a PodGroup isn't removed while any of its Pods is non-terminal. |
| **Controller- vs user-managed** | Usually Jobs create them. You can create them yourself for full control of names. |
| **Consistency** | All Pods in a group need the same `schedulerName`, `priority` and `preemptionPolicy`, or the whole group is unschedulable. |
| **Immutable** | `spec.schedulingGroup` on a Pod. |
| **Status caveat** | Status reflects the **initial** placement only. It isn't updated when Pods later fail or are evicted. |

---

## Lab 1 – Owned by the Job, collected with it
```bash
kubectl create namespace pg-life
kubectl create job owner -n pg-life --image=busybox:1.36 --dry-run=client -o json -- sleep 20 \
  | jq '.spec += {"scheduling":{"schedulingPolicy":{"gang":{}}}}' | kubectl apply -f -
kubectl get podgroup -n pg-life -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}/{.items[0].metadata.ownerReferences[0].name}{"\n"}'   # Job/owner
kubectl delete job owner -n pg-life ; sleep 5 ; kubectl get podgroups,workloads -n pg-life     # gone
```

## Lab 2 – Pods can come first; they wait silently
```bash
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: early, namespace: pg-life}
spec:
  schedulingGroup: {podGroupName: later}
  containers: [{name: c, image: registry.k8s.io/pause:3.10}]
YAML
sleep 5 ; kubectl get pod early -n pg-life          # Pending, no events, no conditions
kubectl apply -f - <<'YAML'
apiVersion: scheduling.k8s.io/v1beta1
kind: PodGroup
metadata: {name: later, namespace: pg-life}
spec: {schedulingPolicy: {basic: {}}}
YAML
kubectl wait --for=condition=Ready pod/early -n pg-life      # scheduled once the group exists
```
The docs also say a PodGroup whose `workloadRef` names a missing Workload is **rejected**. On v1.37 it was **accepted**:
```bash
kubectl apply -f - <<'YAML'
apiVersion: scheduling.k8s.io/v1beta1
kind: PodGroup
metadata: {name: dangling, namespace: pg-life}
spec:
  workloadRef: {workloadName: no-such-workload, templateName: worker}
  schedulingPolicy: {gang: {minCount: 1}}
YAML
#   podgroup.scheduling.k8s.io/dangling created
```

## Lab 3 – Deletion protection
```bash
kubectl delete podgroup later -n pg-life --wait=false
kubectl get podgroup later -n pg-life -o jsonpath='deleting={.metadata.deletionTimestamp} finalizers={.metadata.finalizers}{"\n"}'
#   deleting=2026-…  finalizers=["scheduling.k8s.io/podgroup-protection"]
kubectl delete pod early -n pg-life ; sleep 3 ; kubectl get podgroup later -n pg-life      # NotFound - released once no pod runs
```

## Lab 4 – Mixed schedulers in one group
```bash
kubectl apply -f - <<'YAML'
apiVersion: scheduling.k8s.io/v1beta1
kind: PodGroup
metadata: {name: mixed, namespace: pg-life}
spec: {schedulingPolicy: {gang: {minCount: 2}}}
---
apiVersion: v1
kind: Pod
metadata: {name: mixed-1, namespace: pg-life}
spec:
  schedulingGroup: {podGroupName: mixed}
  containers: [{name: c, image: registry.k8s.io/pause:3.10}]
---
apiVersion: v1
kind: Pod
metadata: {name: mixed-2, namespace: pg-life}
spec:
  schedulerName: my-other-scheduler
  schedulingGroup: {podGroupName: mixed}
  containers: [{name: c, image: registry.k8s.io/pause:3.10}]
YAML
sleep 8 ; kubectl get pods -n pg-life mixed-1 mixed-2      # both Pending forever
```
In our run there was no event at all. The default scheduler never sees `minCount` members it's responsible for. For priority mismatches the error **is** explicit: see `../../workload-api/disruption-and-priority`.

---

## Cleanup
```bash
kubectl delete namespace pg-life
```
