# Configure Default Memory Requests and Limits for a Namespace – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/

> The docs' YAML is copied **verbatim**: [01-memory-defaults.yaml](01-memory-defaults.yaml) (LimitRange `mem-limit-range`), then Pods [02](02-memory-defaults-pod.yaml), [03](03-memory-defaults-pod-2.yaml), [04](04-memory-defaults-pod-3.yaml). Namespace `default-mem-example`, as in the docs.

## Key ideas (read first)

| Container specifies | LimitRanger admission sets |
|---|---|
| nothing | request = `defaultRequest` (256Mi), limit = `default` (512Mi) |
| only a limit (1Gi) | request = **the limit** (1Gi), *not* defaultRequest |
| only a request (128Mi) | limit = `default` (512Mi) |
| a request **above** the default limit | **rejected**: request must be ≤ limit |

**Why defaults matter:** a ResourceQuota on `limits.memory`/`requests.memory` rejects every Pod that doesn't declare them (see [../quota-memory-cpu-namespace](../quota-memory-cpu-namespace/)). Defaults fill them in. Defaults are applied **only at Pod creation**. Changing the LimitRange later doesn't touch running Pods.

---

## Step 0
```bash
cd tasks/administer-cluster/manage-resources/memory-default-namespace
kubectl create namespace default-mem-example
kubectl apply -f 01-memory-defaults.yaml --namespace=default-mem-example
```
`R(){ kubectl get pod $1 -n default-mem-example -o jsonpath='{.spec.containers[0].resources}{"\n"}'; }` is a handy shortcut for the checks below.

## Lab 1 – No resources: both defaults
```bash
kubectl apply -f 02-memory-defaults-pod.yaml --namespace=default-mem-example
kubectl get pod default-mem-demo --output=yaml --namespace=default-mem-example | grep -A5 resources:
#   {"limits":{"memory":"512Mi"},"requests":{"memory":"256Mi"}}
kubectl get pod default-mem-demo -n default-mem-example -o jsonpath='{.metadata.annotations.kubernetes\.io/limit-ranger}{"\n"}'
#   LimitRanger plugin set: memory request for container default-mem-demo-ctr; memory limit for container default-mem-demo-ctr
kubectl delete pod default-mem-demo --namespace=default-mem-example
```

## Lab 2 – Only a limit: request copies the limit
```bash
kubectl apply -f 03-memory-defaults-pod-2.yaml --namespace=default-mem-example
kubectl get pod default-mem-demo-2 --output=yaml --namespace=default-mem-example
#   {"limits":{"memory":"1Gi"},"requests":{"memory":"1Gi"}}
```

## Lab 3 – Only a request: limit from the default
```bash
kubectl apply -f 04-memory-defaults-pod-3.yaml --namespace=default-mem-example
kubectl get pod default-mem-demo-3 --output=yaml --namespace=default-mem-example
#   {"limits":{"memory":"512Mi"},"requests":{"memory":"128Mi"}}
```

## Lab 4 (extra) – A request larger than the default limit
```bash
kubectl run over -n default-mem-example --image=nginx \
  --overrides='{"spec":{"containers":[{"name":"over","image":"nginx","resources":{"requests":{"memory":"700Mi"}}}]}}'
#   The Pod "over" is invalid: spec.containers[0].resources.requests: Invalid value: "700Mi": must be less than or equal to memory limit of 512Mi
```

---

## Useful commands
```bash
kubectl describe limitrange -n default-mem-example
kubectl get pods -n default-mem-example -o custom-columns=NAME:.metadata.name,REQ:.spec.containers[0].resources.requests.memory,LIM:.spec.containers[0].resources.limits.memory
```

## Cleanup
```bash
./cleanup.sh        # kubectl delete namespace default-mem-example
```
