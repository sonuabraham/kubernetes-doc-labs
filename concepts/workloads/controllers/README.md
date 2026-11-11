# Workload Management – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/controllers/

> Sub-pages: [deployment](deployment/), [replicaset](replicaset/), [statefulset](statefulset/), [daemonset](daemonset/), [job](job/), [ttlafterfinished](ttlafterfinished/), [cron-jobs](cron-jobs/), [replicationcontroller](replicationcontroller/).

## Key ideas (read first)

| Workload API | Use it for | Pod identity | Lab |
|---|---|---|---|
| **Deployment** (→ ReplicaSet) | Stateless apps. Pods are interchangeable. Rolling updates and rollback. Replaces ReplicationController. | random suffix | [deployment](deployment/) |
| **StatefulSet** | Pods with distinct identity, each linked to its **own PersistentVolume**. A replacement reattaches the same volume. | `name-0`, `name-1`… | [statefulset](statefulset/) |
| **DaemonSet** | Node-local facilities (CNI, storage driver, log/monitoring agents), one per node. | one per node | [daemonset](daemonset/) |
| **Job** | A one-off task that runs **to completion**. | — | [job](job/) |
| **CronJob** | The same Job again on a schedule. | — | [cron-jobs](cron-jobs/) |
| **TTL-after-finished** | Auto-delete finished Jobs. | — | [ttlafterfinished](ttlafterfinished/) |

You create the higher-level object, and the control plane manages the Pods for you, replacing failed ones.

## Quick comparison lab
```bash
kubectl create namespace ctrl-demo
kubectl create deployment d -n ctrl-demo --image=registry.k8s.io/pause:3.10 --replicas=2
kubectl create job j -n ctrl-demo --image=busybox:1.36 -- echo done
kubectl create cronjob cj -n ctrl-demo --image=busybox:1.36 --schedule='*/1 * * * *' -- date
kubectl get deploy,rs,job,cronjob,pods -n ctrl-demo
kubectl api-resources --api-group=apps ; kubectl api-resources --api-group=batch
#   apps:  daemonsets deployments replicasets statefulsets controllerrevisions
#   batch: cronjobs jobs
kubectl delete namespace ctrl-demo
```
