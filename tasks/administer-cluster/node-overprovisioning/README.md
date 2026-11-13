# Overprovision Node Capacity For A Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/node-overprovisioning/

> The docs' YAML is copied **verbatim**: [01-low-priority-class.yaml](01-low-priority-class.yaml) and [02-deployment-with-capacity-reservation.yaml](02-deployment-with-capacity-reservation.yaml). It goes into the namespace **`example`**, the name used in the docs' command. [03-real-workload.yaml](03-real-workload.yaml) is extra: it's the "real" workload that makes the placeholders give way.
>
> minikube has a single node and no node autoscaler, so the lab shows the half that Kubernetes itself does: placeholders hold capacity and are **preempted** the moment real Pods need it. On a cloud cluster, the now-Pending placeholders then trigger the autoscaler to add a node.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Placeholder Pods** | `pause` containers that only *request* CPU and memory. They hold spare room on the nodes. |
| **Negative PriorityClass** | `placeholder` has value `-1000`, lower than every normal Pod (default priority 0). So placeholders are always the first to be preempted, and they can never preempt anything. |
| **Preemption** | When a higher-priority Pod doesn't fit, the scheduler evicts lower-priority Pods on a node to make room. The real Pod starts **without waiting for a new node**. |
| **Autoscaler loop** | Evicted placeholders go Pending, the cluster autoscaler or Karpenter sees unschedulable Pods and adds a node, and the placeholders land there. So spare room is always there *before* it's needed. |
| **Sizing** | Total reserve = replicas × per-Pod requests (e.g. 5 × 100m/200Mi = 500m / 1Gi). |
| **Anti-affinity** | The example's *preferred* anti-affinity spreads placeholders across nodes. (Its `topologyKey: topology.kubernetes.io/hostname` isn't a standard node label; minikube's node only has `kubernetes.io/hostname`. So the preference never matches here, which is harmless because it's only *preferred*.) Karpenter treats preferred rules as hard, so the replica count can become a minimum node count. |

```
 node (8 CPU)                                    node (8 CPU)
 ┌───────────────────────────────┐   real-app   ┌───────────────────────────────┐
 │ system 0.95 │ P P P P P P P   │  ───────────►│ system │ real real │ P P P P   │   3 P preempted → Pending
 │             │ 7 × 1 CPU       │  2 × 1.5 CPU │        │           │           │   (autoscaler would add a node)
 └───────────────────────────────┘              └───────────────────────────────┘
```

---

## Step 0
```bash
cd tasks/administer-cluster/node-overprovisioning
kubectl create ns example
```

## Lab 1 – PriorityClass and placeholder Deployment
```bash
kubectl apply -f 01-low-priority-class.yaml
kubectl get priorityclass
#   NAME                      VALUE        GLOBAL-DEFAULT   PREEMPTIONPOLICY
#   placeholder               -1000        false            PreemptLowerPriority
#   system-cluster-critical   2000000000   false            PreemptLowerPriority
#   system-node-critical      2000001000   false            PreemptLowerPriority
kubectl --namespace example apply -f 02-deployment-with-capacity-reservation.yaml
kubectl -n example get po -o custom-columns=NAME:.metadata.name,PRIO:.spec.priority,CLASS:.spec.priorityClassName
#   capacity-reservation-...   -1000   placeholder        <- the admission plugin resolved the class into spec.priority
```

## Lab 2 – Adjust the requests and the replica count (the docs' numbers)
The docs edit with `kubectl edit deployment capacity-reservation`. Here sed is the "editor":
```bash
KUBE_EDITOR='sed -i -e "s/cpu: 50m/cpu: 100m/" -e "s/memory: 512Mi/memory: 200Mi/" -e "/limits:/a\            cpu: 100m"' \
  kubectl -n example edit deployment capacity-reservation
kubectl -n example get deploy capacity-reservation -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
#   {"limits":{"cpu":"100m","memory":"200Mi"},"requests":{"cpu":"100m","memory":"200Mi"}}
kubectl -n example scale deployment capacity-reservation --replicas=5
kubectl -n example get deployment capacity-reservation
#   NAME                   READY   UP-TO-DATE   AVAILABLE   AGE
#   capacity-reservation   5/5     5            5           2m          <- reserving 500m CPU / 1Gi
```

## Lab 3 – Fill the node with placeholders, then let real work in
This node has 8 CPUs and about 0.95 CPU is already requested by system Pods. Make 7 placeholders of 1 CPU each, which fills the node:
```bash
KUBE_EDITOR='sed -i -e "s/cpu: 100m/cpu: \"1\"/"' kubectl -n example edit deployment capacity-reservation
kubectl -n example scale deployment capacity-reservation --replicas=7
kubectl -n example get deploy capacity-reservation          # 7/7
kubectl -n example apply -f 03-real-workload.yaml           # 2 × 1.5 CPU, priority 0
kubectl -n example get po -o wide --sort-by=.metadata.creationTimestamp
#   capacity-reservation-...-v8hhx   Running   minikube
#   ... (4 Running)
#   capacity-reservation-...-2qmq6   Pending   <none>      <- replacements for the preempted ones
#   capacity-reservation-...-kzwbd   Pending   <none>
#   capacity-reservation-...-zslrz   Pending   <none>
#   real-app-...-75hrp               Running   minikube    <- started immediately
#   real-app-...-c7pbz               Running   minikube
kubectl -n example get events --field-selector reason=Preempted -o custom-columns=OBJ:.involvedObject.name,MSG:.message
#   capacity-reservation-...-4msbk   Preempted by pod 56770078-... on node minikube
#   capacity-reservation-...-jd7sm   Preempted by pod 56770078-... on node minikube
#   capacity-reservation-...-k8fvx   Preempted by pod 487de02b-... on node minikube
kubectl -n example get deploy
#   capacity-reservation   4/7     <- 3 placeholders wait for a new node (a cloud autoscaler would add one now)
#   real-app               2/2
```
3 placeholders went because 2 × 1.5 CPU needed 3 CPUs. The Pending placeholders can't get their room back: with priority −1000 they can't preempt `real-app`. Scale `real-app` to 0 and they're scheduled again.

---

## Useful commands
```bash
kubectl get pc
kubectl get po -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,PRIO:.spec.priority --sort-by=.spec.priority
kubectl describe node <n> | grep -A8 "Allocated resources"
kubectl get events -A --field-selector reason=Preempted
```

## Cleanup
```bash
./cleanup.sh        # namespace example + PriorityClass placeholder
```
