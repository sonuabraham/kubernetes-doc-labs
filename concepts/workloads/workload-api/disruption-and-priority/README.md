# Pod Group Disruption and Priority – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/workload-api/disruption-and-priority/

> Cluster: the `wl-lab` profile (`../start-wl-lab.sh`). The fields used to need `WorkloadAwarePreemption` (v1.36), which is merged into `GenericWorkload` in v1.37.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **disruptionMode `single`** | Pods of the group can be preempted or disrupted **individually**. |
| **disruptionMode `all`** | The group is disrupted **as a unit**: preempting one member means preempting all of them. Natural for gangs, where a partial gang is useless. Not allowed with the `basic` policy. |
| **Group priority** | `priorityClassName` on the PodGroup (or template) resolves to `priority`. The scheduler treats the **group** as one preemption unit at that priority. |
| **preemptionPolicy** | `PreemptLowerPriority` (default) or `Never`, per group (CompositePodGroups too, `PodGroupPreemptionPolicy` alpha). |
| **Consistency rule** | All Pods in a PodGroup must have the **same** `.spec.priority` (and preemptionPolicy and schedulerName) as the group. Otherwise the whole group is unschedulable. |
| **CompositePodGroup** | Can carry its own priority, disruption mode and preemption policy for the subtree. |

## The demo app
[podgroup-priority.yaml](podgroup-priority.yaml) is the docs' PodGroup `job-1` in `ns-1` with `priorityClassName: high-priority`, **verbatim**. [01-podgroup-priority-runnable.yaml](01-podgroup-priority-runnable.yaml) is the same with the required `schedulingPolicy` (gang 2) and `disruptionMode: all`.

---

## Lab 1 – The docs' excerpt needs a scheduling policy
```bash
cd concepts/workloads/workload-api/disruption-and-priority
kubectl apply -f ../00-prereqs.yaml          # PriorityClass high-priority (value 10000)
kubectl create namespace ns-1
kubectl apply -f podgroup-priority.yaml
#   The PodGroup "job-1" is invalid: spec.schedulingPolicy: Invalid value: "": must specify one of: `basic`, `gang`
kubectl apply -f 01-podgroup-priority-runnable.yaml
kubectl get podgroup job-1 -n ns-1 -o jsonpath='{.spec}{"\n"}'
#   {"disruptionMode":{"all":{}},"preemptionPolicy":"PreemptLowerPriority","priority":10000,"priorityClassName":"high-priority","schedulingPolicy":{"gang":{"minCount":2}}}
```

## Lab 2 – Members must match the group's priority
```bash
for i in 1 2; do kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: m$i, namespace: ns-1}
spec:
  schedulingGroup: {podGroupName: job-1}
  containers: [{name: c, image: registry.k8s.io/pause:3.10}]
YAML
done
sleep 8 ; kubectl get pods -n ns-1                 # both Pending
kubectl get events -n ns-1 -o custom-columns=M:.message | tail -1
#   all pods in a single pod group should have the same priority as the pod group's priority, got 0 and 10000
kubectl get podgroup job-1 -n ns-1 -o jsonpath='{.status.conditions[0].reason}{"\n"}'    # SchedulerError
```
Fix: give the pods `priorityClassName: high-priority`:
```bash
kubectl delete pod m1 m2 -n ns-1
for i in 1 2; do kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: m$i, namespace: ns-1}
spec:
  priorityClassName: high-priority
  schedulingGroup: {podGroupName: job-1}
  containers: [{name: c, image: registry.k8s.io/pause:3.10}]
YAML
done
kubectl wait --for=condition=Ready pod/m1 pod/m2 -n ns-1 ; kubectl get podgroup job-1 -n ns-1      # Scheduled
```

## Lab 3 – `all` needs a gang
```bash
kubectl create job basic-all --image=busybox:1.36 --dry-run=client -o json -- true \
  | jq '.spec.scheduling={"schedulingPolicy":{"basic":{}},"disruptionMode":{"all":{}}}' | kubectl apply --dry-run=server -f -
#   spec.scheduling.disruptionMode: ... the disruptionMode `all` is not supported with the Basic scheduling policy
```
The preemption unit must not be bigger than the scheduling unit.

---

## Cleanup
```bash
kubectl delete namespace ns-1
```
