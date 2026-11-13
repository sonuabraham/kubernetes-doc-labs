# Configure Memory and CPU Quotas for a Namespace – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/quota-memory-cpu-namespace/

> The docs' YAML is copied **verbatim**: [01-quota-mem-cpu.yaml](01-quota-mem-cpu.yaml) (ResourceQuota `mem-cpu-demo`), [02-quota-mem-cpu-pod.yaml](02-quota-mem-cpu-pod.yaml), [03-quota-mem-cpu-pod-2.yaml](03-quota-mem-cpu-pod-2.yaml). Namespace `quota-mem-cpu-example`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Aggregate caps** | Sum over all Pods in the namespace: requests.cpu ≤ 1, requests.memory ≤ 1Gi, limits.cpu ≤ 2, limits.memory ≤ 2Gi. |
| **Must declare** | Once a quota tracks a resource, **every container must set it**. Otherwise it's Forbidden. Use a LimitRange to supply defaults ([../memory-default-namespace](../memory-default-namespace/)). |
| **Admission-time** | The check happens when a Pod is created. `status.used` is updated by the quota controller. |
| **vs LimitRange** | LimitRange = per-container min/max/defaults. ResourceQuota = namespace total. |

---

## Step 0
```bash
cd tasks/administer-cluster/manage-resources/quota-memory-cpu-namespace
kubectl create namespace quota-mem-cpu-example
kubectl apply -f 01-quota-mem-cpu.yaml --namespace=quota-mem-cpu-example
kubectl get resourcequota mem-cpu-demo --namespace=quota-mem-cpu-example --output=yaml
```

## Lab 1 – A Pod within the quota
```bash
kubectl apply -f 02-quota-mem-cpu-pod.yaml --namespace=quota-mem-cpu-example
kubectl get pod quota-mem-cpu-demo --namespace=quota-mem-cpu-example
kubectl get resourcequota mem-cpu-demo --namespace=quota-mem-cpu-example -o jsonpath='{ .status.used }' | jq .
#   { "limits.cpu": "800m", "limits.memory": "800Mi", "requests.cpu": "400m", "requests.memory": "600Mi" }
```

## Lab 2 – A second Pod that would exceed it
```bash
kubectl apply -f 03-quota-mem-cpu-pod-2.yaml --namespace=quota-mem-cpu-example
#   Error from server (Forbidden): ... pods "quota-mem-cpu-demo-2" is forbidden: exceeded quota: mem-cpu-demo,
#   requested: requests.memory=700Mi, used: requests.memory=600Mi, limited: requests.memory=1Gi
```
600Mi + 700Mi > 1Gi. Only the memory request breaks the quota: CPU (400m+400m ≤ 1) and the limits would fit.

## Lab 3 (extra) – A Pod without resources
```bash
kubectl run bare -n quota-mem-cpu-example --image=nginx
#   Error from server (Forbidden): pods "bare" is forbidden: failed quota: mem-cpu-demo: must specify limits.cpu for: bare;
#   limits.memory for: bare; requests.cpu for: bare; requests.memory for: bare
kubectl describe quota mem-cpu-demo -n quota-mem-cpu-example
#   Resource         Used   Hard
#   limits.cpu       800m   2
#   limits.memory    800Mi  2Gi
#   requests.cpu     400m   1
#   requests.memory  600Mi  1Gi
```

---

## Useful commands
```bash
kubectl describe quota -n quota-mem-cpu-example
kubectl get resourcequota -A
```

## Cleanup
```bash
./cleanup.sh        # kubectl delete namespace quota-mem-cpu-example
```
