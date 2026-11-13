# Configure Minimum and Maximum CPU Constraints for a Namespace – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/cpu-constraint-namespace/

> The docs' YAML is copied **verbatim**: [01-cpu-constraints.yaml](01-cpu-constraints.yaml) (LimitRange `cpu-min-max-demo-lr`: min 200m, max 800m), then Pods [02](02-cpu-constraints-pod.yaml) to [05](05-cpu-constraints-pod-4.yaml). Pod 4 uses the docs' `vish/stress` image. Namespace `constraints-cpu-example`. This is the CPU twin of [../memory-constraint-namespace](../memory-constraint-namespace/).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **min / max** | Per container: CPU request ≥ 200m, CPU limit ≤ 800m. Otherwise Forbidden. |
| **Implicit defaults** | `default` = `defaultRequest` = max (800m), filled in by the API server. |
| **Requests vs node** | Even an allowed request must still fit on a node to be scheduled. |

---

## Step 0
```bash
cd tasks/administer-cluster/manage-resources/cpu-constraint-namespace
kubectl create namespace constraints-cpu-example
kubectl apply -f 01-cpu-constraints.yaml --namespace=constraints-cpu-example
kubectl get limitrange cpu-min-max-demo-lr --output=yaml --namespace=constraints-cpu-example
#   default: {cpu: 800m}  defaultRequest: {cpu: 800m}  max: {cpu: 800m}  min: {cpu: 200m}
```

## Lab 1 – Within range
```bash
kubectl apply -f 02-cpu-constraints-pod.yaml --namespace=constraints-cpu-example
kubectl get pod constraints-cpu-demo --namespace=constraints-cpu-example
#   constraints-cpu-demo   1/1   Running
kubectl get pod constraints-cpu-demo -n constraints-cpu-example -o jsonpath='{.spec.containers[0].resources}{"\n"}'
#   {"limits":{"cpu":"800m"},"requests":{"cpu":"500m"}}
kubectl delete pod constraints-cpu-demo --namespace=constraints-cpu-example
```

## Lab 2 – Out of range
```bash
kubectl apply -f 03-cpu-constraints-pod-2.yaml --namespace=constraints-cpu-example
#   Error from server (Forbidden): ... maximum cpu usage per Container is 800m, but limit is 1500m
kubectl apply -f 04-cpu-constraints-pod-3.yaml --namespace=constraints-cpu-example
#   Error from server (Forbidden): ... minimum cpu usage per Container is 200m, but request is 100m
```

## Lab 3 – No resources
```bash
kubectl apply -f 05-cpu-constraints-pod-4.yaml --namespace=constraints-cpu-example
kubectl get pod constraints-cpu-demo-4 --namespace=constraints-cpu-example --output=yaml | grep -A4 resources:
#   {"limits":{"cpu":"800m"},"requests":{"cpu":"800m"}}
kubectl delete pod constraints-cpu-demo-4 --namespace=constraints-cpu-example
```

---

## Useful commands
```bash
kubectl describe limitrange -n constraints-cpu-example
kubectl top pod -n constraints-cpu-example          # metrics-server: vish/stress is throttled at the 800m limit
```

## Cleanup
```bash
./cleanup.sh        # kubectl delete namespace constraints-cpu-example
```
