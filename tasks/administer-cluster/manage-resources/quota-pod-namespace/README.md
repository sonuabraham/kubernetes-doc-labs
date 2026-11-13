# Configure a Pod Quota for a Namespace – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/quota-pod-namespace/

> The docs' YAML is copied **verbatim**: [01-quota-pod.yaml](01-quota-pod.yaml) (ResourceQuota `pod-demo`, `pods: "2"`) and [02-quota-pod-deployment.yaml](02-quota-pod-deployment.yaml) (3 replicas). Namespace `quota-pod-example`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Object-count quota** | `pods: "2"` caps the number of non-terminal Pods in the namespace. |
| **Controllers don't fail loudly** | The Deployment is accepted. Its ReplicaSet just can't create the 3rd Pod and retries, so you see it in events and in the `ReplicaFailure` condition. |
| **Rollouts** | With the quota full, a RollingUpdate that needs a surge Pod blocks. Leave headroom or use `maxSurge: 0`. |

---

## Step 0
```bash
cd tasks/administer-cluster/manage-resources/quota-pod-namespace
kubectl create namespace quota-pod-example
kubectl apply -f 01-quota-pod.yaml --namespace=quota-pod-example
kubectl get resourcequota pod-demo --namespace=quota-pod-example --output=yaml
#   status: {hard: {pods: "2"}, used: {pods: "0"}}
```

## Lab 1 – A 3-replica Deployment
```bash
kubectl apply -f 02-quota-pod-deployment.yaml --namespace=quota-pod-example
kubectl get deployment pod-quota-demo --namespace=quota-pod-example --output=yaml | grep -A20 "^status:"
#   availableReplicas: 2
#   conditions:
#   - type: Available       reason: MinimumReplicasUnavailable   message: Deployment does not have minimum availability.
#   - type: ReplicaFailure  reason: FailedCreate                 message: <text of the ReplicaSet's last create error>
#   readyReplicas: 2   replicas: 2   unavailableReplicas: 1
kubectl get resourcequota pod-demo -n quota-pod-example -o jsonpath='{.status}{"\n"}'
#   {"hard":{"pods":"2"},"used":{"pods":"2"}}
kubectl get events -n quota-pod-example --field-selector reason=FailedCreate -o custom-columns=MSG:.message
#   Error creating: pods "pod-quota-demo-58b4cdfbbf-7djtk" is forbidden: exceeded quota: pod-demo, requested: pods=1, used: pods=2, limited: pods=2
```
(In this run, the first FailedCreate event happened to read `Error creating: Unauthorized` and was copied into the condition. That was a transient controller credential hiccup; the following events all show the quota message.)

## Lab 2 (extra) – Make room
```bash
kubectl scale deployment pod-quota-demo -n quota-pod-example --replicas=2
kubectl get deployment pod-quota-demo -n quota-pod-example      # 2/2: the quota now matches the desired replicas
```

---

## Useful commands
```bash
kubectl describe quota -n quota-pod-example
kubectl get rs -n quota-pod-example -o jsonpath='{.items[*].status.conditions}'
```

## Cleanup
```bash
./cleanup.sh        # kubectl delete namespace quota-pod-example
```
