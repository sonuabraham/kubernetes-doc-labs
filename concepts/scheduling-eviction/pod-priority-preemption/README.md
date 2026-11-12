# Pod Priority and Preemption – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/

> The docs' manifests are **verbatim**: [priorityclass-high-priority.yaml](priorityclass-high-priority.yaml), [priorityclass-high-priority-nonpreempting.yaml](priorityclass-high-priority-nonpreempting.yaml), [pod-nginx-high-priority.yaml](pod-nginx-high-priority.yaml), [node-disable-resize-preemption.yaml](node-disable-resize-preemption.yaml). [00-low.yaml](00-low.yaml) adds a low class for victims. All contention happens on the 4-CPU **fake nodes** (`../fake-nodes.sh up 3`).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **PriorityClass** | Cluster-scoped name → integer `value` (≤ 1 billion for users; `system-*` classes go to 2 billion+). `globalDefault` for Pods without a class (else 0). |
| **Priority admission** | Resolves `priorityClassName` into `spec.priority` + `preemptionPolicy`. Setting `priority` yourself is **forbidden**. |
| **Scheduling order** | The queue is sorted by priority: higher-priority Pending Pods are tried first. |
| **Preemption** | If a Pod fits nowhere, the scheduler picks a node where evicting **lower-priority** Pods makes room, deletes them (graceful), and sets `status.nominatedNodeName`. |
| **preemptionPolicy: Never** | Jumps the queue, but **never evicts** anyone. |
| **Victim choice** | Fewest/lowest-priority victims; **PDBs** respected best-effort; affinity to lower-priority Pods and cross-node preemption aren't handled. |
| **Resize preemption** | Preempting to make room for an in-place resize (`InPlacePodVerticalScalingSchedulerPreemption`, alpha), opt out per node with `spec.podPreemptionPolicy`. |
| **QoS ≠ priority** | Kubelet eviction under node pressure looks at usage vs requests first and priority second. Scheduler preemption uses priority only. |

---

## Step 1
```bash
cd concepts/scheduling-eviction/pod-priority-preemption
kubectl create ns prio-demo ; N="-n prio-demo"
kubectl apply -f priorityclass-high-priority.yaml -f priorityclass-high-priority-nonpreempting.yaml -f 00-low.yaml
kubectl get priorityclass
#   high-priority 1000000 PreemptLowerPriority | high-priority-nonpreempting 1000000 Never | low-priority 100
#   system-cluster-critical 2000000000 | system-node-critical 2000001000
kubectl apply $N -f pod-nginx-high-priority.yaml
kubectl get pod nginx $N -o jsonpath='{.spec.priority} {.spec.preemptionPolicy}'     # 1000000 PreemptLowerPriority
kubectl run setprio $N --image=nginx --overrides='{"spec":{"priority":5}}'
#   forbidden: the integer value of priority (5) must not be provided in pod spec; priority admission controller computed ...
```

## Lab 1 – Non-preempting vs preempting (one 4-CPU node)
```bash
# low-1, low-2 (low-priority, 1.5 CPU each) pinned to fake-1 → both bound (3 CPU + kindnet 100m)
# nonpre (high-priority-nonpreempting, 1.5 CPU):
#   Pending: "... preemption: not eligible due to preemptionPolicy=Never."
# high (high-priority, 1.5 CPU):
#   high   NOMINATED fake-1        low-2   DELETING        event on low-2: "Preempted by pod 30ac… on node fake-1"
kubectl delete pod low-2 $N --grace-period=0 --force      # fake node: finish the eviction by hand
#   high → fake-1
```

## Lab 2 – Queue order
```bash
# low-3 (low-priority) is Pending BEFORE we free space; nonpre (1000000) is also Pending
kubectl delete pod low-1 $N --grace-period=0 --force
#   nonpre → fake-1      low-3 → <none>        <- the higher priority Pod gets the freed space, even though it can't preempt
```

## Lab 3 – PodDisruptionBudgets in victim selection
```bash
# v-2 on fake-2 (3 CPU, PDB minAvailable 1 → ALLOWED DISRUPTIONS 0), v-3 on fake-3 (3 CPU, no PDB)
# h2 (high-priority, 3 CPU, may go to fake-2 or fake-3):
#   h2 NOMINATED fake-3, v-3 DELETING, v-2 untouched
```
Best effort: if only PDB-protected victims exist, they're preempted anyway.

## Lab 4 – Disable resize preemption per node (docs, alpha)
```bash
kubectl apply -f node-disable-resize-preemption.yaml --dry-run=server -o jsonpath='{.spec}'
#   {"taints":[{"effect":"NoSchedule","key":"node.kubernetes.io/not-ready"}]}     <- podPreemptionPolicy silently dropped: gate off
```

## Gotcha found on fake nodes
A first run looked wrong: `low-2` itself showed `NOMINATED fake-1`. The fake node still had a **Terminating** kindnet Pod (100m, priority 0) from the taint lab, which still counted, so `low-2` tried to preempt it. That's the docs' *"Pods are preempted, but the preemptor is not scheduled"*: the preemptor waits for victims to finish terminating.

---

## Useful commands
```bash
kubectl get priorityclass
kubectl get pods -o custom-columns=NAME:.metadata.name,PRIO:.spec.priority,NODE:.spec.nodeName,NOMINATED:.status.nominatedNodeName
kubectl get events --field-selector reason=Preempted -A
```

## Cleanup
```bash
./cleanup.sh
```
