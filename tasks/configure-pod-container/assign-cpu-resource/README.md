# Assign CPU Resources to Containers and Pods – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-resource/

> Runs on the default **minikube** cluster (8 CPUs, metrics-server enabled). The docs' YAML is copied **verbatim**: [01-cpu-request-limit.yaml](01-cpu-request-limit.yaml) and [02-cpu-request-limit-2.yaml](02-cpu-request-limit-2.yaml). Namespace `cpu-example`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **CPU unit** | 1 CPU = 1 core/hyperthread. `0.5` = `500m`. The precision is 1m. |
| **Request** | Used for scheduling, and becomes the cgroup `cpu.weight` (a relative share under contention). |
| **Limit** | Enforced with CFS quota (cgroup `cpu.max`): the container is **throttled**, never killed, when it wants more. |
| **No limit** | The container may use all idle CPU on the node, or a LimitRange default if one applies. |
| **Too big a request** | Pending forever with `Insufficient cpu`. |

---

## Step 0
```bash
cd tasks/configure-pod-container/assign-cpu-resource
kubectl create namespace cpu-example
```

## Lab 1 – Request 0.5, limit 1, try to use 2
```bash
kubectl apply -f 01-cpu-request-limit.yaml --namespace=cpu-example
kubectl get pod cpu-demo --output=yaml --namespace=cpu-example | grep -A4 "^    resources:"
#   limits: {cpu: "1"}   requests: {cpu: 500m}       <- "0.5" is stored as 500m
sleep 40; kubectl top pod cpu-demo --namespace=cpu-example
#   NAME       CPU(cores)   MEMORY(bytes)
#   cpu-demo   1003m        1Mi                 <- the process wants 2 CPUs (-cpus 2) but is throttled at the 1-CPU limit
```
The image has no shell, so look at its cgroup from the node:
```bash
U=$(kubectl get pod cpu-demo -n cpu-example -o jsonpath='{.metadata.uid}' | tr - _)
minikube ssh -- "sudo cat /sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod$U.slice/cpu.max /sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod$U.slice/cpu.weight"
#   100000 100000        <- quota 100ms per 100ms period = 1 CPU
#   20                   <- cpu.weight from the 500m request (cgroup v2 weight, vs 79 for 2000m ...)
kubectl delete pod cpu-demo --namespace=cpu-example
```

## Lab 2 – A request too big for the node (100 CPUs)
```bash
kubectl apply -f 02-cpu-request-limit-2.yaml --namespace=cpu-example
kubectl get pod cpu-demo-2 --namespace=cpu-example                # Pending
kubectl describe pod cpu-demo-2 --namespace=cpu-example
#   Warning  FailedScheduling  default-scheduler  0/1 nodes are available: 1 Insufficient cpu. preemption: ... Preemption is not helpful for scheduling.
```

---

## Useful commands
```bash
kubectl top pod -n cpu-example
kubectl describe node <n> | grep -A10 "Allocated resources"
```

## Cleanup
```bash
kubectl delete namespace cpu-example
```
