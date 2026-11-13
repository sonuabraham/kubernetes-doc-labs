# Configure Minimum and Maximum Memory Constraints for a Namespace – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-constraint-namespace/

> The docs' YAML is copied **verbatim**: [01-memory-constraints.yaml](01-memory-constraints.yaml) (LimitRange `mem-min-max-demo-lr`: min 500Mi, max 1Gi), then Pods [02](02-memory-constraints-pod.yaml) to [05](05-memory-constraints-pod-4.yaml). Namespace `constraints-mem-example`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **min / max** | Per container: request ≥ `min`, limit ≤ `max`. Violations are **Forbidden** at admission. Nothing is ever scheduled. |
| **Implicit defaults** | A LimitRange with only min/max still gets `default` and `defaultRequest` = **max** (the API server fills them in). A container with no resources therefore gets 1Gi/1Gi. |
| **Only at creation** | Existing Pods aren't re-checked when the LimitRange changes. |
| **Use case** | Keep Pods within what the nodes can actually hold (e.g. nodes with 2 GiB), or give tiers (prod/dev) different sizes. |

---

## Step 0
```bash
cd tasks/administer-cluster/manage-resources/memory-constraint-namespace
kubectl create namespace constraints-mem-example
kubectl apply -f 01-memory-constraints.yaml --namespace=constraints-mem-example
kubectl get limitrange mem-min-max-demo-lr --namespace=constraints-mem-example --output=yaml
#   limits:
#   - default: {memory: 1Gi}  defaultRequest: {memory: 1Gi}  max: {memory: 1Gi}  min: {memory: 500Mi}  type: Container
#     ^ added by the API server: not in the file
```

## Lab 1 – Within range
```bash
kubectl apply -f 02-memory-constraints-pod.yaml --namespace=constraints-mem-example
kubectl get pod constraints-mem-demo -n constraints-mem-example -o jsonpath='{.spec.containers[0].resources}{"\n"}'
#   {"limits":{"memory":"800Mi"},"requests":{"memory":"600Mi"}}
kubectl delete pod constraints-mem-demo --namespace=constraints-mem-example
```

## Lab 2 – Limit above max, request below min
```bash
kubectl apply -f 03-memory-constraints-pod-2.yaml --namespace=constraints-mem-example
#   Error from server (Forbidden): ... pods "constraints-mem-demo-2" is forbidden: maximum memory usage per Container is 1Gi, but limit is 1536Mi
kubectl apply -f 04-memory-constraints-pod-3.yaml --namespace=constraints-mem-example
#   Error from server (Forbidden): ... pods "constraints-mem-demo-3" is forbidden: minimum memory usage per Container is 500Mi, but request is 100Mi
```

## Lab 3 – No resources: gets the implicit defaults
```bash
kubectl apply -f 05-memory-constraints-pod-4.yaml --namespace=constraints-mem-example
kubectl get pod constraints-mem-demo-4 --namespace=constraints-mem-example --output=yaml | grep -A4 resources:
#   {"limits":{"memory":"1Gi"},"requests":{"memory":"1Gi"}}
kubectl describe pod constraints-mem-demo-4 --namespace=constraints-mem-example | grep -A3 Limits
kubectl delete pod constraints-mem-demo-4 --namespace=constraints-mem-example
```

---

## Useful commands
```bash
kubectl describe limitrange -n constraints-mem-example
```

## Cleanup
```bash
./cleanup.sh        # kubectl delete namespace constraints-mem-example
```
