# Topology-Aware Workload Scheduling – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/workload-api/topology-aware-scheduling/

> Cluster: the `wl-lab` profile (`../start-wl-lab.sh`), with `TopologyAwareWorkloadScheduling` (alpha) on. One node, so one topology domain. That's enough to see "must fit inside **one** domain". With several nodes per domain you'd see the scheduler pick a domain for the whole group.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Topology constraint** | `schedulingConstraints.topology: [{key: <node label>}]`: **all Pods of the group must land in nodes sharing the same value** of that label (same rack, zone, NVLink domain…). At most one constraint per group. |
| **With gang** | The scheduler looks for **one domain** that can hold `minCount` Pods together. Otherwise the group is unschedulable, even if the cluster as a whole has room. |
| **With basic** | Pods are placed individually, but all within the domain picked for the group. |
| **Multi-level** | CompositePodGroup on `zone`, child PodGroups on `rack`: the whole job stays in one zone, and each child group stays in one rack inside it. |

## The demo app
The docs examples are **verbatim**: [podgroup-rack.yaml](podgroup-rack.yaml) (gang 4, key `topology.example.com/rack`), [workload-multilevel.yaml](workload-multilevel.yaml) (zone → rack templates) and [compositepodgroup-and-podgroups.yaml](compositepodgroup-and-podgroups.yaml) (the runtime objects for that Workload). [../03-gang-topology.yaml](../03-gang-topology.yaml) has two gang Jobs with a zone constraint (4 × 3 CPU and 2 × 3 CPU).

---

## Lab 1 – The docs objects
```bash
cd concepts/workloads/workload-api/topology-aware-scheduling
kubectl apply -f podgroup-rack.yaml -f workload-multilevel.yaml -f compositepodgroup-and-podgroups.yaml
kubectl get workloads,compositepodgroups,podgroups
#   compositepodgroup workload-root   Gang  example-workload
#   podgroup example-podgroup / workload-workers / workload-driver   Gang  Pending   <- no pods yet
kubectl get podgroup workload-workers -o jsonpath='{.spec.schedulingConstraints}{"  parent="}{.spec.parentCompositePodGroupName}{"\n"}'
```

## Lab 2 – "Fits the cluster" is not enough
```bash
kubectl label node wl-lab topology.kubernetes.io/zone=zone-a
kubectl create namespace gang-demo
kubectl apply -f ../03-gang-topology.yaml ; sleep 15
kubectl get pods -n gang-demo -o custom-columns=JOB:.metadata.labels.job-name,PHASE:.status.phase,NODE:.spec.nodeName --no-headers | sort | uniq -c
#   4 zone-gang-big   Pending          <- 12 CPU needed in ONE zone; zone-a has 8
#   2 zone-gang-small Running wl-lab   <- 6 CPU fits inside zone-a
kubectl get podgroups -n gang-demo     # zone-gang-big Unschedulable, zone-gang-small Scheduled
```
On a 2-node, 2-zone cluster (8 CPU each), `zone-gang-big` would **still** fail even though the cluster has 16 CPUs. That's the point of the constraint: keep tightly coupled pods close together.

---

## Cleanup
```bash
kubectl delete namespace gang-demo ; kubectl label node wl-lab topology.kubernetes.io/zone-
kubectl delete -f compositepodgroup-and-podgroups.yaml -f workload-multilevel.yaml -f podgroup-rack.yaml
```
