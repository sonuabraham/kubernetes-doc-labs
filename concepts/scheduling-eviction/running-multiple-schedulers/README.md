# Running Multiple Schedulers – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/running-multiple-schedulers/

> The page describes three deployment strategies. This lab runs each as extra kube-scheduler Deployments (same image as the control plane), on the shared fake nodes (`../fake-nodes.sh up 3`).

## Key ideas (read first)

| Strategy | How | Trade-off |
|---|---|---|
| **HA standby replicas** | N replicas of one scheduler, **leader election** on a Lease | Only the leader schedules. A standby takes over on failure. |
| **Multiple profiles, one instance** | One process, several `profiles[].schedulerName` | **Shared cache and queue**: profiles see each other's decisions, so no double booking |
| **Multiple separate instances** | Several scheduler Deployments | **No coordination**: they can bind conflicting Pods (the same last CPU) |
| **Mixing with custom schedulers** | kube-scheduler + a third-party scheduler | Give them **disjoint node pools** (taints, labels) |
| **Choosing** | Pods pick one with `spec.schedulerName` (default `default-scheduler`) | |

---

## Step 1
```bash
cd concepts/scheduling-eviction ; ./fake-nodes.sh up 3 ; cd running-multiple-schedulers
kubectl apply -f 00-rbac.yaml -f 01-ha-scheduler.yaml -f 02-two-profiles.yaml -f 03-independent.yaml
```

## Lab 1 – HA: one leader, failover
```bash
kubectl get lease ha-scheduler -n multi-sched -o jsonpath='{.spec.holderIdentity}'     # ha-scheduler-…-qhgzc_e123…
# schedule a Pod with schedulerName: ha-scheduler, then count bindings per replica:
for p in $(kubectl get pods -n multi-sched -l app=ha-scheduler -o name); do echo "$p $(kubectl logs -n multi-sched $p | grep -c 'Successfully bound')"; done
#   …-cxxpg 0      <- standby: idle
#   …-qhgzc 1      <- leader
kubectl delete pod <leader> -n multi-sched
#   new leader ha-scheduler-…-cxxpg after 1s       <- the old leader RELEASED the lease on shutdown (holder briefly ""), the standby took it at once
```
A crashed (not gracefully stopped) leader would only be replaced after the lease duration (15s by default).

## Lab 2 – Two profiles in one process
```bash
# 3 Pods × 1 CPU via each profile (nodeSelector type=fake):
kubectl get pods -n multi-sched -o custom-columns=POD:.metadata.name,SCHED:.spec.schedulerName,NODE:.spec.nodeName | grep -E 'pack|spread'
#   pack-1    packer     fake-1
#   pack-2    packer     fake-1
#   pack-3    packer     fake-1      <- MostAllocated: fill one node first (bin packing, see ../resource-bin-packing)
#   spread-1  spreader   fake-2
#   spread-2  spreader   fake-3
#   spread-3  spreader   fake-2      <- LeastAllocated (default): emptiest node first
```

## Lab 3 – Separate instances can double-book
```bash
./race.sh 5            # race-a (indep-a) and race-b (indep-b): 3 CPU each, both pinned to the 4-CPU fake-3, created simultaneously
#   round 1: race-a= race-b=fake-3
#   round 2: race-a= race-b=fake-3
#   round 3: race-a= race-b=fake-3
#   round 4: race-a=fake-3 race-b=fake-3      <- BOTH bound: 6 CPU on a 4-CPU node
#   round 5: race-a=fake-3 race-b=
```
Usually the second scheduler sees the first binding in time. Sometimes it doesn't, and the node is **overcommitted**. A real kubelet would then reject one Pod (`OutOfcpu`, see `../../security/hardening-guide/scheduler`). With the default scheduler alone the third Pod gets `0/4 nodes are available: 1 Insufficient cpu, ...`. That's why the page recommends **profiles in one instance**, or **disjoint node pools** for separate schedulers.

---

## Useful commands
```bash
kubectl get pods -A -o custom-columns=NAME:.metadata.name,SCHEDULER:.spec.schedulerName,NODE:.spec.nodeName
kubectl get leases -A | grep -i sched
kubectl get events -A --field-selector reason=Scheduled -o custom-columns=FROM:.reportingComponent,MSG:.message
```

## Cleanup
```bash
./cleanup.sh
```
