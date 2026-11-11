# Container Lifecycle Hooks – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **PostStart** | Runs right after the container is created, **concurrently** with the ENTRYPOINT: before, during or after it. No parameters. The container isn't reported `Running` until the hook finishes. |
| **PreStop** | Runs right before the container is stopped (API delete, failed liveness/startup probe, preemption, resource pressure…). It must **finish before** the stop signal is sent. The **grace period clock is already running** during the hook. |
| **StopSignal** | `lifecycle.stopSignal` overrides the image's `STOPSIGNAL`. Needs `spec.os.name`. Behind the `ContainerStopSignals` feature gate (alpha). |
| **Handler types** | `exec` (runs **inside** the container; resources count against it), `httpGet` (the kubelet calls the container), `sleep` (the kubelet waits). `tcpSocket` is deprecated. |
| **Failure** | A failed PostStart **or** PreStop hook **kills the container**, with events `FailedPostStartHook` / `FailedPreStopHook`. Hook output isn't logged, only the failure event. |
| **Grace period** | `terminationGracePeriodSeconds` covers hook + shutdown **together**. Docs example: 60s grace, a 55s hook and a 10s shutdown means the container is SIGKILLed. |
| **Delivery** | **At least once**. A hook may run twice (for example after a kubelet restart), so make it idempotent. |

## The demo app
| File | What |
|---|---|
| [lifecycle-events.yaml](lifecycle-events.yaml) | The docs' `lifecycle-demo` (nginx, postStart writes `/usr/share/message`, preStop `nginx -s quit`), **verbatim** |
| [01-lifecycle-events-badcommand.yaml](01-lifecycle-events-badcommand.yaml) | The same with postStart = `badcommand`, as the docs suggest |
| [02-poststart-concurrency.yaml](02-poststart-concurrency.yaml) | A 10s postStart next to a main loop that logs every second |
| [03-prestop-grace.yaml](03-prestop-grace.yaml) | The docs' 60/55/10 arithmetic scaled down to 10/8/5 |
| [04-http-poststart.yaml](04-http-poststart.yaml) | httpGet postStart that fails |
| [05-sleep-prestop.yaml](05-sleep-prestop.yaml) | `sleep` preStop handler |
| [06-stop-signal.yaml](06-stop-signal.yaml) | `stopSignal: SIGUSR1` |

---

## Lab 1 – The docs example
```bash
cd concepts/containers/container-lifecycle-hooks
kubectl apply -f 00-namespace.yaml
kubectl apply -f lifecycle-events.yaml -n hooks-demo
kubectl wait --for=condition=Ready pod/lifecycle-demo -n hooks-demo
kubectl exec lifecycle-demo -n hooks-demo -- cat /usr/share/message     # Hello from the postStart handler
kubectl delete pod lifecycle-demo -n hooks-demo                          # preStop: nginx -s quit, wait until nginx is gone
```

## Lab 2 – A failing hook kills the container (FailedPostStartHook)
```bash
kubectl apply -f 01-lifecycle-events-badcommand.yaml -n hooks-demo
sleep 15
kubectl get events -n hooks-demo --field-selector involvedObject.name=lifecycle-demo -o custom-columns=REASON:.reason,MESSAGE:.message | grep -E 'FailedPostStart|Killing|BackOff'
#   FailedPostStartHook   PostStartHook failed
#   Killing               FailedPostStartHook
#   BackOff               Back-off restarting failed container ...
kubectl delete pod lifecycle-demo -n hooks-demo
```
Pod specs are mostly immutable, so `kubectl apply` over the running `lifecycle-demo` is rejected (`pod updates may not change fields…`). Delete the pod first.

## Lab 3 – PostStart runs concurrently, and holds back "Running"
```bash
kubectl apply -f 02-poststart-concurrency.yaml ; sleep 4
kubectl get pod poststart-slow -n hooks-demo          # 0/1 ContainerCreating  <- the main process IS running, but the hook isn't done
sleep 10 ; kubectl exec poststart-slow -n hooks-demo -- head -14 /tmp/main.log
#   main-12:36:45 hook-start-12:36:45 main-12:36:46 main-12:36:47 ... main-12:36:54 hook-end-12:36:55
```
The main loop and the hook started in the **same second** and kept running side by side.

## Lab 4 – PreStop and the grace period
```bash
kubectl apply -f 03-prestop-grace.yaml ; kubectl wait --for=condition=Ready pod/prestop-slow -n hooks-demo
kubectl logs -f prestop-slow -n hooks-demo &
time kubectl delete pod prestop-slow -n hooks-demo
```
Expected:
```
started
got TERM at 12:37:03          <- TERM only after the 8s preStop hook
                              <- "clean exit" never printed: the 5s shutdown didn't fit into the remaining 2s
real  0m11s                   <- SIGKILL at the 10s grace period
```
Set `terminationGracePeriodSeconds: 20` and repeat. Now you see `clean exit`.

## Lab 5 – httpGet postStart: the race the docs warn about
```bash
kubectl apply -f 04-http-poststart.yaml ; sleep 12
kubectl get pod http-poststart -n hooks-demo          # PostStartHookError, RESTARTS 1+
kubectl get events -n hooks-demo --field-selector involvedObject.name=http-poststart -o custom-columns=R:.reason,M:.message | grep -i hook
#   FailedPostStartHook   PostStartHook failed      <- 404 for /started (or nginx not listening yet) -> container killed
kubectl delete pod http-poststart -n hooks-demo --grace-period=1
```

## Lab 6 – The sleep handler
```bash
kubectl apply -f 05-sleep-prestop.yaml ; kubectl wait --for=condition=Ready pod/sleep-prestop -n hooks-demo
time kubectl delete pod sleep-prestop -n hooks-demo           # ~6s
kubectl run plain -n hooks-demo --image=nginx:1.27 ; kubectl wait --for=condition=Ready pod/plain -n hooks-demo
time kubectl delete pod plain -n hooks-demo                    # ~1s
```
The kubelet waited 5s before signalling. In real setups this gives Service endpoints and load balancers time to stop sending traffic.

## Lab 7 – StopSignal (alpha)
```bash
kubectl apply -f 06-stop-signal.yaml --dry-run=server -o jsonpath='{.spec.containers[0].lifecycle}{"\n"}'
#   (empty) - the field was DROPPED
kubectl get --raw /metrics | grep 'kubernetes_feature_enabled{name="ContainerStopSignals"'
#   kubernetes_feature_enabled{name="ContainerStopSignals",stage="ALPHA"} 0
kubectl apply -f 06-stop-signal.yaml ; kubectl wait --for=condition=Ready pod/stop-signal -n hooks-demo
kubectl logs -f stop-signal -n hooks-demo &  kubectl delete pod stop-signal -n hooks-demo
#   got TERM          <- not USR1: with the gate off, the default signal is used
```
Enabling it needs `--feature-gates=ContainerStopSignals=true` on the API server **and** the kubelet. Without it, set `STOPSIGNAL` in the image.

---

## Useful commands
```bash
kubectl explain pod.spec.containers.lifecycle
kubectl get events --field-selector reason=FailedPostStartHook
kubectl get events --field-selector reason=FailedPreStopHook
kubectl delete pod <pod> --grace-period=<s>
```

## Cleanup
```bash
./cleanup.sh
```
