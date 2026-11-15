# Debug Init Containers – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-application/debug-init-containers/

> The page uses placeholders (`<pod-name>`, `<init-container-1>`, `<init-container-2>`). [init-debug-demo.yaml](init-debug-demo.yaml)
> (not from the docs) is a Pod with exactly those two init containers: the first succeeds, the second waits for a Service `mydb`
> that doesn't exist yet. Runs on the default **minikube** cluster, `default` namespace.
> Background: [configure-pod-initialization](../../../configure-pod-container/configure-pod-initialization/).

## Key ideas (read first)

| Status | Meaning |
|---|---|
| `Init:N/M` | N of M init containers have completed |
| `Init:Error` | an init container exited non-zero (just now) |
| `Init:CrashLoopBackOff` | …and keeps doing so, so the kubelet waits longer between retries |
| `Pending` | init containers haven't started yet |
| `PodInitializing` / `Running` | init containers are done |

The `RESTARTS` column of `kubectl get pod` counts **app** containers only. Init container restarts are in
`status.initContainerStatuses[].restartCount`.

---

## Step 0
```bash
cd tasks/debug/debug-application/debug-init-containers
kubectl apply -f init-debug-demo.yaml
```

## Lab 1 – Status over time (docs: `kubectl get pod <pod-name>`)
```bash
watch -n3 kubectl get pod init-debug-demo
#   t+3s   Init:0/2
#   t+9s   Init:1/2                 <- init-container-1 done (5 s sleep)
#   t+21s  Init:Error               <- init-container-2 gave up
#   t+33s  Init:1/2                 <- retried …
#   later  Init:CrashLoopBackOff / Init:Error, alternating, with growing back-off
```

## Lab 2 – Details (docs: `kubectl describe` and the Go template)
```bash
kubectl describe pod init-debug-demo | sed -n '/^Init Containers:/,/^Containers:/p'
```
```
  init-container-1:
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
    Ready:          True
    Restart Count:  0
  init-container-2:
    State:          Terminated
      Reason:       Error
      Exit Code:    1
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
    Ready:          False
    Restart Count:  4
```
```bash
kubectl get pod init-debug-demo --template '{{.status.initContainerStatuses}}'      # the same, as Go maps
kubectl get pod init-debug-demo -o jsonpath='{.status.containerStatuses[0].state}'  # {"waiting":{"reason":"PodInitializing"}}
```

## Lab 3 – Logs, with `set -x` (docs)
```bash
kubectl logs init-debug-demo -c init-container-2
```
```
+ nslookup mydb.default.svc.cluster.local          <- set -x shows each command as it runs
Server:   10.96.0.10
** server can't find mydb.default.svc.cluster.local: NXDOMAIN
…
mydb never showed up
```

## Lab 4 – Fix the cause, and the Pod recovers by itself (not from the docs)
```bash
kubectl create service clusterip mydb --tcp=5432:5432
# within the next back-off retry (up to 5 min):
kubectl get pod init-debug-demo
#   init-debug-demo   1/1   Running   0   3m33s
kubectl logs init-debug-demo -c init-container-2 | tail -2
#   Name:    mydb.default.svc.cluster.local
#   Address: 10.103.47.213
```
No need to delete the Pod: the kubelet keeps retrying the failed init container.

## Useful commands
```bash
kubectl get pod <p> -o jsonpath='{range .status.initContainerStatuses[*]}{.name}{" ready="}{.ready}{" restarts="}{.restartCount}{"\n"}{end}'
kubectl logs <p> -c <init-container> [--previous]
```

## Cleanup
```bash
./cleanup.sh
```
