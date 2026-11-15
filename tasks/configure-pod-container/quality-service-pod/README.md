# Configure Quality of Service for Pods – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/

> Runs on the default **minikube** cluster. Files: [qos-pod.yaml](qos-pod.yaml), [qos-pod-2.yaml](qos-pod-2.yaml),
> [qos-pod-3.yaml](qos-pod-3.yaml), [qos-pod-4.yaml](qos-pod-4.yaml) (docs, **verbatim**). Not from the docs:
> [qos-pod-limits-only.yaml](qos-pod-limits-only.yaml), [qos-pod-init.yaml](qos-pod-init.yaml).
> Concept background: [concepts/workloads/pods/pod-qos](../../../concepts/workloads/pods/pod-qos/).

## Key ideas (read first)

| Class | Rule (all containers, **init containers included**) | Node effect, measured below |
|---|---|---|
| **Guaranteed** | every container has cpu **and** memory, with request = limit | own pod slice directly under `kubepods.slice`, `oom_score_adj` **-997**, evicted last |
| **Burstable** | not Guaranteed, and at least one cpu/memory request or limit | `kubepods-burstable.slice`, `oom_score_adj` = `1000 - 1000*memRequest/nodeMemory`, clamped to 2..999 |
| **BestEffort** | no cpu/memory requests or limits at all | `kubepods-besteffort.slice`, `oom_score_adj` **1000**, killed and evicted first |
| **Fixed** | Set at creation and never changes. A resize that would change it is rejected (see [resize lab](../resize-container-resources/)). | |
| **Limit only** | If only a limit is set, the request defaults to the limit, so cpu+memory limits alone give Guaranteed. | |
| **Ephemeral containers** | can't have resources, so they don't count | |

---

## Step 0
```bash
cd tasks/configure-pod-container/quality-service-pod
kubectl create namespace qos-example
```

## Lab 1 – Guaranteed, Burstable, BestEffort, two containers (the docs' Pods)
```bash
kubectl apply -f qos-pod.yaml   --namespace=qos-example     # 700m/200Mi, request = limit
kubectl apply -f qos-pod-2.yaml --namespace=qos-example     # memory 100Mi request, 200Mi limit
kubectl apply -f qos-pod-3.yaml --namespace=qos-example     # nothing
kubectl apply -f qos-pod-4.yaml --namespace=qos-example     # ctr-1 memory request 200Mi, ctr-2 (redis) nothing
kubectl --namespace=qos-example get pod qos-demo-4 -o jsonpath='{ .status.qosClass}{"\n"}'
#   Burstable
```

## Lab 2 – Two edge cases (not from the docs)
```bash
kubectl apply -f qos-pod-limits-only.yaml   # limits only
kubectl apply -f qos-pod-init.yaml          # app container Guaranteed-style, init container without resources
kubectl wait --for=condition=Ready pod --all -n qos-example
kubectl get pods -n qos-example -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass,REQ:.spec.containers[*].resources.requests
```
```
NAME         QOS          REQ
qos-demo     Guaranteed   map[cpu:700m memory:200Mi]
qos-demo-2   Burstable    map[memory:100Mi]
qos-demo-3   BestEffort   <none>
qos-demo-4   Burstable    map[memory:200Mi]
qos-demo-5   Guaranteed   map[cpu:700m memory:200Mi]   <- requests were filled in from the limits
qos-demo-6   Burstable    map[cpu:700m memory:200Mi]   <- the resource-less init container makes it Burstable
```

## Lab 3 – What the class changes on the node (not from the docs)
Each container's `oom_score_adj` and the QoS cgroup slice it lives in:
```bash
for p in qos-demo qos-demo-2 qos-demo-3 qos-demo-4; do
  for c in $(kubectl -n qos-example get po $p -o jsonpath='{range .status.containerStatuses[*]}{.name}={.containerID}{" "}{end}'); do
    id=${c##*//}
    echo "$p ${c%%=*} $(minikube ssh -- "pid=\$(sudo crictl inspect -o go-template --template '{{.info.pid}}' $id);
      echo \$(cat /proc/\$pid/oom_score_adj) \$(cut -d: -f3 /proc/\$pid/cgroup | cut -d/ -f3)" | tr -d '\r')"
  done
done
```
```
qos-demo   qos-demo-ctr      -997  kubepods-pod46fefddc_….slice   <- Guaranteed: no QoS sub-slice
qos-demo-2 qos-demo-2-ctr     997  kubepods-burstable.slice
qos-demo-3 qos-demo-3-ctr    1000  kubepods-besteffort.slice
qos-demo-4 qos-demo-4-ctr-1   994  kubepods-burstable.slice       <- 200Mi request: protected a bit more
qos-demo-4 qos-demo-4-ctr-2   999  kubepods-burstable.slice       <- no request of its own: 999
```
Check the Burstable formula against the node (capacity 31826084Ki):
```bash
Ki=$(kubectl get node minikube -o jsonpath='{.status.capacity.memory}'); Ki=${Ki%Ki}
echo $(( 1000 - (1000 * 100 * 1024) / Ki )) $(( 1000 - (1000 * 200 * 1024) / Ki ))
#   997 994
```
So when the node runs out of memory, the kernel OOM killer picks BestEffort first. Among Burstable containers it kills
the one with the smallest request first. Guaranteed goes last. Kubelet node-pressure eviction ranks Pods in the same order
(see [concepts/scheduling-eviction](../../../concepts/scheduling-eviction/node-pressure-eviction/)).

CPU share follows the request: `cpu.weight` inside the container cgroup is **76** for qos-demo (700m) and **1**
(the minimum) for qos-demo-2 and qos-demo-3, which request no CPU.
```bash
for p in qos-demo qos-demo-2 qos-demo-3; do echo "$p $(kubectl -n qos-example exec $p -- cat /sys/fs/cgroup/cpu.weight)"; done
```

## Useful commands
```bash
kubectl get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,QOS:.status.qosClass
kubectl get pod <p> -o jsonpath='{.status.qosClass}{"\n"}'
```

## Cleanup
```bash
./cleanup.sh     # kubectl delete namespace qos-example
```
