# Workloads – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/

> Sub-sections: [pods](pods/), [controllers](controllers/) (Deployment, ReplicaSet, StatefulSet, DaemonSet, Job, TTL, CronJob, ReplicationController), [management](management/), [autoscaling](autoscaling/), [workload-api](workload-api/), [podgroup-api](podgroup-api/), [compositepodgroup-api](compositepodgroup-api/).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Workload** | An application running on Kubernetes, always inside **Pods** (one or more containers). |
| **Pod failure is final** | If a Pod's node dies, that Pod is gone for good. Recovery means a **new** Pod, so don't manage Pods by hand. |
| **Workload resources** | Controllers that keep the right number of the right Pods running. |
| **Deployment / ReplicaSet** | Stateless; Pods are interchangeable. They replaced the legacy ReplicationController. |
| **StatefulSet** | Pods with a stable identity (`db-0`, `db-1`) and **their own** PersistentVolume each. |
| **DaemonSet** | One Pod per (matching) node, for node-local facilities: networking, log agents, monitoring. New nodes get one automatically. |
| **Job / CronJob** | Run to completion once / on a schedule. |
| **Custom workloads** | Third-party controllers through CRDs, for example "all-or-nothing" groups. |
| **Workload placement** | `GenericWorkload` (beta): the **Workload API** defines `PodGroupTemplates`. Controllers create **PodGroups**, and Pods point to them with `spec.schedulingGroup` for gang scheduling (all or nothing). **Disabled by default on minikube v1.37**, see [workload-api](workload-api/). |

## The demo app
[00-all-kinds.yaml](00-all-kinds.yaml): namespace `workloads-demo` with one **bare Pod**, a Deployment `web` (2), a StatefulSet `db` (2, with PVCs), a DaemonSet `agent`, a Job `once` and a CronJob `every-minute`. Every pod carries a `kind` label.

---

## Lab 1 – One of each
```bash
cd concepts/workloads
kubectl apply -f 00-all-kinds.yaml
sleep 70          # let the CronJob fire once
kubectl get pods -n workloads-demo --sort-by=.metadata.name \
  -o custom-columns=NAME:.metadata.name,KIND:.metadata.labels.kind,STATUS:.status.phase,OWNER:.metadata.ownerReferences[0].kind
```
Expected:
```
NAME                          KIND          STATUS      OWNER
agent-hb9wl                   daemonset     Running     DaemonSet     <- one per node (1 node here)
bare                          bare          Running     <none>        <- nobody owns it
db-0 / db-1                   statefulset   Running     StatefulSet   <- ordinal names
every-minute-29906688-f5mkp   cronjob       Succeeded   Job           <- CronJob -> Job -> Pod
once-vlqw9                    job           Succeeded   Job           <- ran to completion
web-6895f4789-cpkxc           deployment    Running     ReplicaSet    <- Deployment -> ReplicaSet -> Pod, random names
```
```bash
kubectl get pvc -n workloads-demo       # data-db-0, data-db-1 - one volume PER StatefulSet pod
```

## Lab 2 – Who brings a Pod back?
```bash
kubectl delete pod bare -n workloads-demo
kubectl delete pod -n workloads-demo -l kind=deployment --wait=false
kubectl delete pod db-0 -n workloads-demo --wait=false
sleep 5 ; kubectl get pods -n workloads-demo -l 'kind in (bare,deployment,statefulset)'
#   (no "bare")                         <- gone for good
#   web-6895f4789-6sg56, -hnl8z         <- NEW names, interchangeable
#   db-0, db-1                          <- db-0 is back with the SAME name (and the same PVC)
```

## Lab 3 – Is the Workload API available?
```bash
kubectl api-resources | grep -i -E 'workload|podgroup'          # nothing on default minikube
kubectl get --raw /metrics | grep 'feature_enabled{name="GenericWorkload"'
#   kubernetes_feature_enabled{name="GenericWorkload",stage="BETA"} 0      <- beta, but off by default
```
[workload-api](workload-api/) shows how to start a cluster with it turned on.

---

## Cleanup
```bash
./cleanup.sh
```
