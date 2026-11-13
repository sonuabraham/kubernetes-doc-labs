# Autoscale the DNS Service in a Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/dns-horizontal-autoscaling/

> Runs on the default **minikube** cluster (1 node, 8 cores, CoreDNS at 1 replica). [dns-horizontal-autoscaler.yaml](dns-horizontal-autoscaler.yaml) is the docs' manifest **verbatim**, with its `<SCALE_TARGET>` placeholder. It's filled at apply time with `sed`. [set-params.sh](set-params.sh) is a non-interactive `kubectl edit configmap kube-dns-autoscaler`. [cleanup.sh](cleanup.sh) puts CoreDNS back to 1 replica.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **cluster-proportional-autoscaler** | A separate Deployment. It polls the node list (count and total cores) and **sets `replicas` on the target** through the scale subresource. It's not an HPA and ignores load. |
| **linear** | `replicas = max(ceil(cores / coresPerReplica), ceil(nodes / nodesPerReplica))`, bounded by `min`/`max`. `preventSinglePointFailure` gives ≥2 replicas when there are >1 nodes. |
| **ladder** | Step tables: `coresToReplicas` / `nodesToReplicas` as `[[threshold, replicas], ...]`. The higher of the two results wins. |
| **ConfigMap** | `kube-dns-autoscaler` holds the params. It's created from `--default-params` only if **missing**, and changes are picked up live (no restart). |
| **It owns `replicas`** | A manual `kubectl scale coredns` is reverted at the next poll. |
| **Disable** | Scale the autoscaler to 0, or delete it (or, with the old Addon Manager, delete its manifest from `/etc/kubernetes/addons/`). |

---

## Step 0 – Is it already there? What's the target?
```bash
cd tasks/administer-cluster/dns-horizontal-autoscaling
kubectl get deployment --namespace=kube-system
#   coredns               1/1   ...     metrics-server   1/1   ...    snapshot-controller   2/2      <- no kube-dns-autoscaler
kubectl get deployment -l k8s-app=kube-dns --namespace=kube-system
#   coredns   1/1   1   1   6d3h          -> scale target: Deployment/coredns
```

## Lab 1 – Enable DNS horizontal autoscaling
```bash
sed 's|<SCALE_TARGET>|Deployment/coredns|' dns-horizontal-autoscaler.yaml | kubectl apply -f -
#   serviceaccount/kube-dns-autoscaler created
#   clusterrole.rbac.authorization.k8s.io/system:kube-dns-autoscaler created
#   clusterrolebinding.rbac.authorization.k8s.io/system:kube-dns-autoscaler created
#   deployment.apps/kube-dns-autoscaler created
kubectl get configmap kube-dns-autoscaler --namespace=kube-system -o jsonpath='{.data}{"\n"}'
#   {"linear":"{\"coresPerReplica\":256,\"includeUnschedulableNodes\":true,\"nodesPerReplica\":16,\"preventSinglePointFailure\":true}"}
kubectl -n kube-system logs deploy/kube-dns-autoscaler | head -5
#   Created ConfigMap kube-dns-autoscaler in namespace kube-system      <- from --default-params
#   Set control mode to linear
kubectl get deployment coredns -n kube-system          # still 1: max(ceil(8/256), ceil(1/16)) = 1
```

## Lab 2 – Tune: linear
```bash
./set-params.sh 'linear: '"'"'{"coresPerReplica":2,"includeUnschedulableNodes":true,"nodesPerReplica":16,"preventSinglePointFailure":true}'"'"''
#   configmap/kube-dns-autoscaler edited
sleep 15; kubectl get deployment coredns -n kube-system
#   coredns   2/4   4   2              <- ceil(8 cores / 2) = 4
kubectl -n kube-system logs deploy/kube-dns-autoscaler --tail=2
#   Replicas are not as expected : updating replicas from 1 to 4
```

## Lab 3 – Tune: ladder (the other control pattern)
```bash
./set-params.sh 'ladder: '"'"'{"coresToReplicas":[[1,1],[4,2],[8,3]],"nodesToReplicas":[[1,1],[2,2]]}'"'"''
sleep 15; kubectl -n kube-system logs deploy/kube-dns-autoscaler --tail=1
#   Replicas are not as expected : updating replicas from 4 to 3     <- 8 cores -> step [8,3]
```

## Lab 4 – Manual scaling loses
```bash
kubectl scale deployment coredns -n kube-system --replicas=1
sleep 15; kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.replicas}{"\n"}'
#   3
kubectl -n kube-system logs deploy/kube-dns-autoscaler | grep "not as expected" | tail -1
#   Replicas are not as expected : updating replicas from 1 to 3
```

## Lab 5 – Disable it
**Option 1: scale the autoscaler to 0.**
```bash
kubectl scale deployment --replicas=0 kube-dns-autoscaler --namespace=kube-system
#   deployment.apps/kube-dns-autoscaler scaled
kubectl get rs --namespace=kube-system -l k8s-app=kube-dns-autoscaler
#   NAME                             DESIRED   CURRENT   READY   AGE
#   kube-dns-autoscaler-784d4cd6c6   0         0         0       103s
kubectl scale deployment coredns -n kube-system --replicas=1        # sticks now
```
**Option 2: delete it.**
```bash
kubectl delete deployment kube-dns-autoscaler --namespace=kube-system
#   deployment.apps "kube-dns-autoscaler" deleted
kubectl get configmap kube-dns-autoscaler -n kube-system      # still there: re-deploying would reuse the ladder params
```
Option 3 (Addon Manager manifest under `/etc/kubernetes/addons/dns-horizontal-autoscaler/`) doesn't apply. minikube's `/etc/kubernetes/addons` holds its own addons, which don't include this one.

---

## Useful commands
```bash
kubectl -n kube-system get cm kube-dns-autoscaler -o jsonpath='{.data}'
kubectl -n kube-system logs deploy/kube-dns-autoscaler -f
kubectl get deploy coredns -n kube-system -w
```

## Cleanup
```bash
./cleanup.sh     # autoscaler + ConfigMap + RBAC; CoreDNS back to 1 replica
```
