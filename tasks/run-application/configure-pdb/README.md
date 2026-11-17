# Specifying a Disruption Budget for your Application – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/run-application/configure-pdb/

> Runs on the default **minikube** cluster, `default` namespace. Files: [zookeeper-pod-disruption-budget-minavailable.yaml](zookeeper-pod-disruption-budget-minavailable.yaml),
> [zookeeper-pod-disruption-budget-maxunavailable.yaml](zookeeper-pod-disruption-budget-maxunavailable.yaml) (docs, **verbatim**).
> Not from the docs: [zk-standin.yaml](zk-standin.yaml) (3 nginx Pods labelled `app: zookeeper`, readiness switchable with `touch /tmp/unready`)
> and [evict.sh](evict.sh) (calls the Eviction API for one Pod, which is what `kubectl drain` does, without draining the only node).
> Concept background: [concepts/workloads/pods/disruptions](../../../concepts/workloads/pods/disruptions/).
>
> All statements on the page checked out. Two extra details: a single-replica workload with `maxUnavailable: 10%` can always be evicted
> (`desiredHealthy=0`), and an evicted **bare** Pod is simply gone.

## Key ideas (read first)

| Field / rule | Meaning |
|---|---|
| `minAvailable` / `maxUnavailable` | one of them; integer or percentage. Both are **rounded up** (min 50% of 7 = 4; max 30% of 7 = 3) |
| Status | `expectedPods`, `currentHealthy` (Ready Pods), `desiredHealthy`, `disruptionsAllowed` |
| Only **voluntary** evictions | the Eviction API (drain, cluster autoscaler…) answers **429** when the budget is used up; `kubectl delete pod` ignores PDBs |
| `unhealthyPodEvictionPolicy` | `IfHealthyBudget` (default): unready Pods can be evicted only while the app is healthy; `AlwaysAllow`: unready Pods always |
| Bare Pods / custom selectors | only an **integer** `minAvailable` works |
| Overlap | a Pod covered by two PDBs can't be evicted at all |

---

## Lab 1 – Create the PDB (docs)
```bash
cd tasks/run-application/configure-pdb
kubectl apply -f zookeeper-pod-disruption-budget-minavailable.yaml
kubectl get poddisruptionbudgets
#   zk-pdb   2   N/A   0   0s          <- no matching Pods yet
kubectl apply -f zk-standin.yaml
kubectl get poddisruptionbudgets
#   zk-pdb   2   N/A   1   1s
kubectl get pdb zk-pdb -o yaml | sed -n '/^status/,$p'
#   conditions: … reason: SufficientPods  type: DisruptionAllowed
#   currentHealthy: 3   desiredHealthy: 2   disruptionsAllowed: 1   expectedPods: 3
```

## Lab 2 – Evictions against the budget (not from the docs)
```bash
./evict.sh zk-0
#   {"kind":"Status",…,"status":"Success","code":201}
./evict.sh zk-1
#   refused (TooManyRequests): Cannot evict pod as it would violate the pod's disruption budget.
kubectl rollout status sts/zk          # zk-0 recreated and Ready → allowed is 1 again
./evict.sh zk-1                        # Success
kubectl apply -f zookeeper-pod-disruption-budget-maxunavailable.yaml     # configured
kubectl get pdb zk-pdb -o jsonpath='{.spec}'
#   {"maxUnavailable":1,"selector":…}  <- apply removed minAvailable (it was in last-applied); same meaning for 3 Pods
```

## Lab 3 – Rounding (docs, measured with 7 replicas)
| Spec (7 Pods) | desiredHealthy | disruptionsAllowed |
|---|---|---|
| `minAvailable: "50%"` | 4 (3.5 rounded up) | 3 |
| `maxUnavailable: "30%"` | 4 | 3 (2.1 rounded up) |
| `maxUnavailable: "10%"` | 6 | 1 (0.7 rounded up) |
| `maxUnavailable: "10%"`, **1** Pod | 0 | 1 (the only Pod may go) |

## Lab 4 – Unhealthy Pod eviction policy (docs)
```bash
kubectl apply -f zookeeper-pod-disruption-budget-minavailable.yaml       # back to minAvailable: 2 (recreate if apply complains)
kubectl exec zk-1 -- touch /tmp/unready; kubectl exec zk-2 -- touch /tmp/unready
kubectl get pdb zk-pdb -o jsonpath='healthy={.status.currentHealthy} desired={.status.desiredHealthy} allowed={.status.disruptionsAllowed}'
#   healthy=1 desired=2 allowed=0
./evict.sh zk-1                        # IfHealthyBudget: refused (app already disrupted, give zk-1 a chance to recover)
kubectl patch pdb zk-pdb --type=merge -p '{"spec":{"unhealthyPodEvictionPolicy":"AlwaysAllow"}}'
./evict.sh zk-1                        # AlwaysAllow: Success (it isn't Ready anyway)
./evict.sh zk-0                        # refused: healthy Pods are still protected
kubectl exec zk-2 -- rm -f /tmp/unready
```

## Lab 5 – Overlap and bare Pods (docs "Arbitrary workloads")
```bash
kubectl create pdb zk-pdb-2 --selector=app=zookeeper --max-unavailable=1
./evict.sh zk-2
#   refused: This pod has more than one PodDisruptionBudget, which the eviction subresource does not support.
kubectl delete pdb zk-pdb-2
for i in 1 2 3; do kubectl run bare-$i --image=nginx:1.27 --labels=app=bare; done
kubectl create pdb bare-max --selector=app=bare --max-unavailable=1
kubectl create pdb bare-pct --selector=app=bare --min-available=50%
kubectl create pdb bare-int --selector=app=bare --min-available=2
kubectl get pdb
#   bare-int   2     N/A   1
#   bare-max   N/A   1     0     <- can't compute: no controller to ask for the desired count
#   bare-pct   50%   N/A   0
kubectl get events --field-selector involvedObject.name=bare-max
#   UnmanagedPods: Pods selected by this PodDisruptionBudget … were found to be unmanaged. … please set ".spec.minAvailable" field of the PDB to an integer value.
kubectl delete pdb bare-max bare-pct
./evict.sh bare-1                      # Success → bare-1 is gone for good (nothing recreates it)
./evict.sh bare-2                      # refused: 2 left = minAvailable
```

## Cleanup
```bash
./cleanup.sh
```
