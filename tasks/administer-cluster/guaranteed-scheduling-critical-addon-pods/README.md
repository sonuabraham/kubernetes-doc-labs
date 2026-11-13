# Guaranteed Scheduling For Critical Add-On Pods – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/guaranteed-scheduling-critical-addon-pods/

> The page has no YAML. It names the two built-in PriorityClasses, `system-cluster-critical` and `system-node-critical`. The manifests here are labelled **not from the docs** and only add Pods that use those names. Everything runs on a throwaway profile **`crit-lab`** (8 allocatable CPUs; minikube's `--cpus` is a quota, not a cpuset).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Critical** | Set `priorityClassName: system-cluster-critical` (2000000000) or `system-node-critical` (2000001000, the highest; the static control-plane Pods use it). |
| **What it buys** | A critical add-on that's evicted or deleted is scheduled **ahead** of ordinary Pending Pods, and if the node is full it **preempts** lower-priority Pods. |
| **What it doesn't** | It doesn't make Pods un-evictable. Only **static** critical Pods can't be evicted by the kubelet. |
| **Namespaces** | Since v1.17 the classes may be used in any namespace. Restrict them with a ResourceQuota `scopeSelector` on `PriorityClass` if needed. |

---

## Step 0
```bash
cd tasks/administer-cluster/guaranteed-scheduling-critical-addon-pods
minikube start -p crit-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
K="kubectl --context crit-lab"
$K get priorityclass
#   system-cluster-critical   2000000000   false   PreemptLowerPriority
#   system-node-critical      2000001000   false   PreemptLowerPriority
$K get po -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.priorityClassName,PRIO:.spec.priority --sort-by=.spec.priority
#   kube-system   storage-provisioner       <none>                 0
#   kube-system   etcd-crit-lab             system-node-critical   2000001000     (static control-plane Pods)
#   kube-system   kube-apiserver-crit-lab   system-node-critical   2000001000   ...
```

## Lab 1 – A full node: ordinary add-on vs critical add-on
```bash
$K apply -f 01-filler.yaml && $K rollout status deploy filler          # 7 x 1 CPU: node full
$K apply -f 02-addon-normal.yaml
$K -n kube-system get po addon-normal                                  # Pending
#   FailedScheduling: 0/1 nodes are available: 1 Insufficient cpu. preemption: ... No preemption victims found for incoming pod.
$K apply -f 03-addon-critical.yaml                                     # priorityClassName: system-cluster-critical
$K -n kube-system get po addon-critical                                # Running
$K get events --field-selector reason=Preempted -o custom-columns=OBJ:.involvedObject.name,MSG:.message
#   filler-8dd688d78-hl2rg   Preempted by pod 79260436-... on node crit-lab
$K get deploy filler                                                   # 6/7 - the ordinary workload made room
```

## Lab 2 – Evicted critical add-ons come back first
```bash
$K -n kube-system delete po addon-normal addon-critical --now          # filler gets back to 7/7
$K apply -f 04-addon-critical-deployment.yaml && $K -n kube-system rollout status deploy addon
$K -n kube-system delete po -l app=lab-addon --now                     # "evict" it
$K -n kube-system get po -l app=lab-addon                              # addon-...-lnpg2   1/1   Running   <- recreated and placed again
$K get deploy filler                                                   # 6/7 - a filler Pod waits instead
```

## Lab 3 – Not limited to kube-system
```bash
$K run crit-in-default --image=registry.k8s.io/pause:3.10 --overrides='{"spec":{"priorityClassName":"system-node-critical"}}'
$K get po crit-in-default -o jsonpath='{.spec.priority}{"\n"}'          # 2000001000 - accepted in "default"
$K delete po crit-in-default
```

---

## Useful commands
```bash
kubectl get pc
kubectl get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,PRIO:.spec.priority --sort-by=.spec.priority
kubectl get events -A --field-selector reason=Preempted
```

## Cleanup
```bash
minikube delete -p crit-lab
```
