# Kubernetes Scheduler – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/

> No YAML on the page. To *see* the scheduler work, [00-verbose-scheduler.yaml](00-verbose-scheduler.yaml) runs a second copy of kube-scheduler (default plugins, profile `verbose-scheduler`) at log level `-v=10`. Multi-node comes from **fake nodes**, see [../README.md](../README.md#multi-node-without-more-minikube-nodes): `../fake-nodes.sh up`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Scheduling** | Picking a node for each Pod without `spec.nodeName`. The kubelet on that node then runs it. |
| **kube-scheduler** | The default scheduler, part of the control plane. Replaceable or extendable (see `../running-multiple-schedulers`, `../scheduling-framework`). |
| **Feasible nodes** | Nodes passing every **filter** (resources, selectors/affinity, taints, ports, volumes…). None → Pod stays **Pending** with a reason per node. |
| **Scoring** | Each score plugin rates each feasible node (0–100, × weight). The highest total wins, ties broken at random. |
| **Binding** | The scheduler writes the choice (Binding subresource → `spec.nodeName`). |
| **Configuring** | Scheduling **profiles** (plugins per extension point). The old "policies" (predicates/priorities) are gone. |

---

## Step 1
```bash
cd concepts/scheduling-eviction
./fake-nodes.sh up 3                     # fake-1..3 (zone-a/b/c), Ready via a heartbeat loop
cd kube-scheduler
kubectl apply -f 00-verbose-scheduler.yaml ; kubectl rollout status deploy/verbose-scheduler -n sched-demo
kubectl label node fake-2 lab/disk=ssd
kubectl apply -n sched-demo -f 01-pods.yaml        # anywhere, picky (nodeSelector lab/disk=ssd), impossible (100 CPUs)
kubectl get pods -n sched-demo -o wide
#   anywhere     Running   minikube
#   picky        Pending   fake-2          <- bound to a fake node: nothing runs it, but the DECISION is what we study
#   impossible   Pending   <none>
```

## Lab 1 – Filtering
```bash
kubectl logs -n sched-demo deploy/verbose-scheduler | grep 'sched-demo/picky' | grep bound
#   "Successfully bound pod to node" pod="sched-demo/picky" node="fake-2" evaluatedNodes=4 feasibleNodes=1
kubectl get events -n sched-demo --field-selector involvedObject.name=impossible -o custom-columns=M:.message
#   0/4 nodes are available: 4 Insufficient cpu. preemption: ... not helpful for scheduling.
```

## Lab 2 – Scoring
```bash
kubectl logs -n sched-demo deploy/verbose-scheduler | grep 'sched-demo/anywhere' | grep -E 'Plugin scored|final score|bound'
#   "Plugin scored node for pod" plugin="TaintToleration"                  node="fake-1"   score=300
#   "Plugin scored node for pod" plugin="NodeResourcesFit"                 node="fake-1"   score=79
#   "Plugin scored node for pod" plugin="NodeResourcesBalancedAllocation"  node="fake-1"   score=74
#   ... (VolumeBinding, DynamicResources, ImageLocality = 0)
#   "Plugin scored node for pod" plugin="NodeResourcesBalancedAllocation"  node="minikube" score=75
#   "Calculated node's final score for pod" node="fake-1" score=453 / fake-2 453 / fake-3 453 / minikube 454
#   "Successfully bound pod to node" pod="sched-demo/anywhere" node="minikube" evaluatedNodes=4 feasibleNodes=4
```
TaintToleration's 300 is 100 × weight 3. minikube won by **one point** of balanced allocation. Scores are weighted per plugin and summed. Plugins and weights: `../scheduling-framework`.

---

## Useful commands
```bash
kubectl get events --field-selector reason=FailedScheduling -A
kubectl get pod <p> -o jsonpath='{.spec.schedulerName} {.spec.nodeName}'
kubectl get --raw /metrics | grep -E '^scheduler_' | head       # (from inside the node: the scheduler's own /metrics)
```

## Cleanup
```bash
./cleanup.sh            # keeps the fake nodes for the other scheduling labs
```
