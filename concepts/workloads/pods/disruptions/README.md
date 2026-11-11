# Disruptions – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/disruptions/

> On single-node minikube we **don't `kubectl drain`** the node, because that would evict the system pods too. Instead [evict.sh](evict.sh) calls the **Eviction API** directly, which is exactly what `drain` does for each pod. For a real 3-node drain like the docs' walk-through, use a multi-node profile (`../../../architecture`).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Involuntary disruptions** | Hardware failure, deleted VM, kernel panic, network partition, node-pressure eviction. A PDB **can't prevent** these, but they **count** against the budget. |
| **Voluntary disruptions** | By the app owner (delete a Deployment or Pod, update the template) or the cluster admin (drain for repair/upgrade, scale-down, defragmentation). |
| **Mitigation** | Resource requests, replicas, spreading (anti-affinity, zones). |
| **PodDisruptionBudget** | Stable. Limits how many Pods of an app can be down **at once from voluntary disruptions that go through the Eviction API**. `minAvailable` or `maxUnavailable` (number or %), plus a label selector. The "intended" count comes from the owner's `.spec.replicas`. |
| **Who respects it** | The **Eviction API** (`kubectl drain`, cluster autoscaler…), which answers **429** when the budget is used up. **`kubectl delete pod/deployment` bypasses it.** Rolling updates aren't limited by PDBs. |
| **unhealthyPodEvictionPolicy** | `IfHealthyBudget` (default: not-ready pods may be evicted only if the app is within budget) or **`AlwaysAllow`** (recommended: lets a drain remove misbehaving pods). |
| **DisruptionTarget condition** | The Pod gets `DisruptionTarget` (reason `EvictionByEvictionAPI`, `PreemptionByScheduler`, …) before it's deleted. See [../pod-condition](../pod-condition/). |

## The demo app
[00-app-with-pdb.yaml](00-app-with-pdb.yaml) mirrors the docs' example: Deployment `app` (3 replicas = pod-a/b/c, each takes ~5s to become Ready), PDB `app-pdb` (`minAvailable: 2`), and unrelated `pod-x` without a PDB. [01-unhealthy-app.yaml](01-unhealthy-app.yaml) adds pods that are never Ready, plus a PDB.

---

## Step 1
```bash
cd concepts/workloads/pods/disruptions
kubectl apply -f 00-app-with-pdb.yaml
kubectl rollout status deploy/app -n disruptions-demo
kubectl get pdb -n disruptions-demo
#   NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS
#   app-pdb   2               N/A               1          <- 3 healthy, need 2 -> 1 may go
```

## Lab 1 – The budget in action (the docs' drain story, by hand)
```bash
P=($(kubectl get pod -n disruptions-demo -l app=quorum -o jsonpath='{.items[*].metadata.name}'))
./evict.sh ${P[0]}        # app-…-fkmdh: evicted                                   ("pod-a evicted")
./evict.sh ${P[1]}        # TooManyRequests: Cannot evict pod as it would violate the pod's disruption budget.
./evict.sh pod-x          # pod-x: evicted                                          (no PDB -> always allowed)
kubectl get pdb app-pdb -n disruptions-demo        # ALLOWED DISRUPTIONS 0
sleep 8                                            # the replacement ("pod-d") becomes Ready
kubectl get pdb app-pdb -n disruptions-demo        # ALLOWED DISRUPTIONS 1
./evict.sh ${P[1]}        # evicted - now it's allowed
```
This is the docs' "drain blocks until pod-d becomes available". `kubectl drain` just retries the 429s until the budget allows the next eviction.

## Lab 2 – Deleting bypasses the budget
```bash
kubectl get pdb app-pdb -n disruptions-demo        # ALLOWED 0 (or 1)
kubectl delete pod -n disruptions-demo $(kubectl get pod -n disruptions-demo -l app=quorum -o jsonpath='{.items[0].metadata.name}')
#   pod "app-…" deleted                            <- no check at all
kubectl get pdb app-pdb -n disruptions-demo        # ALLOWED 0 - and possibly fewer than 2 available now
```
That's the docs' caution: deleting deployments or pods isn't constrained by PDBs. Automation must use the Eviction API.

## Lab 3 – Watch the DisruptionTarget condition
```bash
P=$(kubectl get pod -n disruptions-demo -l app=quorum -o jsonpath='{.items[0].metadata.name}')
./evict.sh $P ; kubectl get pod $P -n disruptions-demo -o jsonpath='{.status.conditions[?(@.type=="DisruptionTarget")]}{"\n"}'
#   {"reason":"EvictionByEvictionAPI","status":"True","type":"DisruptionTarget",...}   (while it terminates; 5s grace)
```

## Lab 4 – Unhealthy pods and unhealthyPodEvictionPolicy
```bash
kubectl apply -f 01-unhealthy-app.yaml ; sleep 10
kubectl get pdb broken-pdb -n disruptions-demo          # ALLOWED DISRUPTIONS 0 - 0 of 2 pods are healthy
B=$(kubectl get pod -n disruptions-demo -l app=broken -o jsonpath='{.items[0].metadata.name}')
./evict.sh $B             # TooManyRequests: Cannot evict pod ... disruption budget.   <- a drain would hang here forever
kubectl patch pdb broken-pdb -n disruptions-demo --type=merge -p '{"spec":{"unhealthyPodEvictionPolicy":"AlwaysAllow"}}'
./evict.sh $B             # evicted - not-ready pods no longer block maintenance
```

## Lab 5 – A rolling update ignores the PDB
```bash
kubectl set env deploy/app -n disruptions-demo V=2
kubectl get pdb app-pdb -n disruptions-demo -w      # ALLOWED can drop to 0 - the Deployment's own maxUnavailable/maxSurge rule, not the PDB
```

---

## Useful commands
```bash
kubectl get pdb -A
kubectl create pdb <name> --selector=app=<x> --min-available=2
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data     # uses the Eviction API, respects PDBs (multi-node clusters!)
kubectl explain pdb.spec
```

## Cleanup
```bash
./cleanup.sh
```
