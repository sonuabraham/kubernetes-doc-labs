# Configure Default CPU Requests and Limits for a Namespace – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/cpu-default-namespace/

> The docs' YAML is copied **verbatim**: [01-cpu-defaults.yaml](01-cpu-defaults.yaml) (LimitRange `cpu-limit-range`: default 1, defaultRequest 0.5), then Pods [02](02-cpu-defaults-pod.yaml), [03](03-cpu-defaults-pod-2.yaml), [04](04-cpu-defaults-pod-3.yaml). Namespace `default-cpu-example`. This is the CPU twin of [../memory-default-namespace](../memory-default-namespace/).

## Key ideas (read first)

| Container specifies | Result |
|---|---|
| nothing | request 500m (defaultRequest), limit 1 (default) |
| only limit `1` | request = limit = 1 |
| only request `0.75` | request 750m, limit 1 (default) |

CPU quantities are normalised: `0.5` is stored as `500m` and `0.75` as `750m`. A CPU limit is enforced by **throttling** (CFS quota), not by killing the container.

---

## Step 0
```bash
cd tasks/administer-cluster/manage-resources/cpu-default-namespace
kubectl create namespace default-cpu-example
kubectl apply -f 01-cpu-defaults.yaml --namespace=default-cpu-example
```

## Lab 1 – No resources
```bash
kubectl apply -f 02-cpu-defaults-pod.yaml --namespace=default-cpu-example
kubectl get pod default-cpu-demo --output=yaml --namespace=default-cpu-example | grep -A5 resources:
#   {"limits":{"cpu":"1"},"requests":{"cpu":"500m"}}
```

## Lab 2 – Only a limit
```bash
kubectl apply -f 03-cpu-defaults-pod-2.yaml --namespace=default-cpu-example
kubectl get pod default-cpu-demo-2 --output=yaml --namespace=default-cpu-example
#   {"limits":{"cpu":"1"},"requests":{"cpu":"1"}}          <- request copied from the limit
```

## Lab 3 – Only a request
```bash
kubectl apply -f 04-cpu-defaults-pod-3.yaml --namespace=default-cpu-example
kubectl get pod default-cpu-demo-3 --output=yaml --namespace=default-cpu-example
#   {"limits":{"cpu":"1"},"requests":{"cpu":"750m"}}
```

---

## Useful commands
```bash
kubectl get limitrange cpu-limit-range -n default-cpu-example -o yaml
kubectl get pods -n default-cpu-example -o custom-columns=NAME:.metadata.name,REQ:.spec.containers[0].resources.requests.cpu,LIM:.spec.containers[0].resources.limits.cpu
```

## Cleanup
```bash
./cleanup.sh        # kubectl delete namespace default-cpu-example
```
