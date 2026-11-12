# Node Autoscaling – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/node-autoscaling/

> The real autoscalers (Cluster Autoscaler, Karpenter) need a cloud provider to create VMs. To see the **control loop** itself, [toy-autoscaler.sh](toy-autoscaler.sh) does the two halves with **fake nodes**: provision a node for unschedulable Pods in pool `elastic`, consolidate nodes that stay empty. Same idea as the toy ingress controller in `../../services-networking/ingress-controllers`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Provisioning** | Unschedulable Pods → simulate scheduling on node *templates* (node groups / NodePools) → create nodes that would fit them. Pod constraints (requests, selectors, affinity, taints) and autoscaler limits decide what's created. |
| **Auto-provisioning** | Choosing the instance type itself (Karpenter, CA node auto-provisioning). |
| **Consolidation** | Remove empty or underused nodes (moving their Pods if allowed, respecting PDBs and `cluster-autoscaler.kubernetes.io/safe-to-evict`). |
| **Cluster Autoscaler** | Works on predefined node groups (cloud ASGs). |
| **Karpenter** | NodePools + provider NodeClasses. Picks instance types per batch of Pods, consolidates actively. |
| **Combine with** | HPA (more Pods → more nodes), VPA (bigger Pods), descheduler, cluster-proportional autoscalers. |

---

## Lab – A toy provision/consolidate loop
```bash
cd concepts/cluster-administration/node-autoscaling
kubectl create ns as-demo
kubectl create deploy batch -n as-demo --image=registry.k8s.io/pause:3.8 --replicas=0
kubectl patch deploy batch -n as-demo -p '{"spec":{"template":{"spec":{"nodeSelector":{"pool":"elastic"},"containers":[{"name":"pause","image":"registry.k8s.io/pause:3.8","resources":{"requests":{"cpu":"1500m"}}}]}}}}'
EMPTY_SECONDS=20 ./toy-autoscaler.sh           # terminal 2
kubectl scale deploy batch -n as-demo --replicas=5
#   18:43:42 PROVISION elastic-1794469422 (pending Pods: 5)
#   18:43:49 PROVISION elastic-1794469428 (pending Pods: 3)
#   18:43:55 PROVISION elastic-1794469435 (pending Pods: 1)
kubectl get pods -n as-demo -o custom-columns=NODE:.spec.nodeName --no-headers | sort | uniq -c
#   2 elastic-…422   2 elastic-…428   1 elastic-…435      <- 2 × 1.5 CPU per 4-CPU node (kindnet takes 100m)
kubectl scale deploy batch -n as-demo --replicas=0
kubectl get pods -n as-demo -o name | xargs -r kubectl delete -n as-demo --grace-period=0 --force      # fake nodes: finish the deletion
#   18:45:25 CONSOLIDATE elastic-…435 (empty 20s)  …and the other two
```
Provisioning is one node per loop. A real autoscaler computes how many nodes the whole pending batch needs (bin-packing simulation) and creates them at once. A first version of the toy only reacted to `Insufficient cpu` messages and never fired: with **no** elastic node at all, the Pods say *"didn't match Pod's node affinity/selector"*. That's exactly why real autoscalers simulate against node **templates** instead of reading scheduler messages.

---

## Useful commands
```bash
kubectl get pods -A --field-selector status.phase=Pending -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,REASON:.status.conditions[0].message
kubectl get nodes -L pool
```

## Cleanup
```bash
./cleanup.sh       # Ctrl-C the toy first
```
