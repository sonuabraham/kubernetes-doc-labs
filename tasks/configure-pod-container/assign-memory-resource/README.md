# Assign Memory Resources to Containers and Pods – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/

> Runs on the default **minikube** cluster (metrics-server addon enabled for `kubectl top`). The docs' YAML is copied **verbatim**: [01-memory-request-limit.yaml](01-memory-request-limit.yaml), [02-memory-request-limit-2.yaml](02-memory-request-limit-2.yaml), [03-memory-request-limit-3.yaml](03-memory-request-limit-3.yaml). Namespace `mem-example`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Request** | What the scheduler reserves on a node. A Pod only fits where `allocatable − sum(requests)` ≥ its request. |
| **Limit** | A hard cap enforced by the kernel (cgroup `memory.max`). Exceeding it gets the container **OOM-killed** (exit 137), and it restarts per `restartPolicy`. |
| **Units** | `Mi`/`Gi` (powers of 2) vs `M`/`G` (powers of 10). `150M` ≈ 143Mi. |
| **No limit** | The container may use all free node memory. A LimitRange default may apply ([../../administer-cluster/manage-resources](../../administer-cluster/manage-resources/)). |
| **Why both** | Requests give scheduling headroom for bursts; limits protect the node. |

---

## Step 0
```bash
cd tasks/configure-pod-container/assign-memory-resource
kubectl get apiservices | grep metrics          # v1beta1.metrics.k8s.io   kube-system/metrics-server   True
kubectl create namespace mem-example
```

## Lab 1 – Request 100Mi, limit 200Mi, use 150M
```bash
kubectl apply -f 01-memory-request-limit.yaml --namespace=mem-example
kubectl get pod memory-demo --output=yaml --namespace=mem-example | grep -A4 "^    resources:"
#   resources: {limits: {memory: 200Mi}, requests: {memory: 100Mi}}
kubectl top pod memory-demo --namespace=mem-example
#   NAME          CPU(cores)   MEMORY(bytes)
#   memory-demo   108m         150Mi                 <- the stress process holds ~150M: above the request, below the limit
kubectl delete pod memory-demo --namespace=mem-example
```

## Lab 2 – Exceed the limit (250M into a 100Mi limit)
```bash
kubectl apply -f 02-memory-request-limit-2.yaml --namespace=mem-example
kubectl get pod memory-demo-2 --namespace=mem-example
#   memory-demo-2   0/1   CrashLoopBackOff   1 (11s ago)   15s
kubectl get pod memory-demo-2 --output=yaml --namespace=mem-example | grep -A6 lastState:
#   lastState: terminated: {exitCode: 137, reason: OOMKilled, ...}
kubectl describe pod memory-demo-2 --namespace=mem-example
#   Last State: Terminated  Reason: OOMKilled  Exit Code: 137   Restart Count: 1
#   Warning  BackOff  kubelet  Back-off restarting failed container memory-demo-2-ctr ...
kubectl delete pod memory-demo-2 --namespace=mem-example
```
The container is killed and restarted again and again. The node itself is unaffected: it's the container's cgroup limit that is enforced.

## Lab 3 – A request too big for any node (1000Gi)
```bash
kubectl apply -f 03-memory-request-limit-3.yaml --namespace=mem-example
kubectl get pod memory-demo-3 --namespace=mem-example          # Pending
kubectl describe pod memory-demo-3 --namespace=mem-example
#   Warning  FailedScheduling  default-scheduler  0/1 nodes are available: 1 Insufficient memory. preemption: ... Preemption is not helpful for scheduling.
kubectl describe nodes | grep -A3 Capacity                     # memory: 31826084Ki - nowhere near 1000Gi
```

---

## Useful commands
```bash
kubectl top pod -n mem-example
kubectl describe node <n> | grep -A10 "Allocated resources"
kubectl get pod <p> -o jsonpath='{.status.containerStatuses[0].lastState}'
```

## Cleanup
```bash
kubectl delete namespace mem-example
```
