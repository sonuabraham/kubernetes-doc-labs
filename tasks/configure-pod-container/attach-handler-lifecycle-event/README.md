# Attach Handlers to Container Lifecycle Events – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/attach-handler-lifecycle-event/

> Runs on the default **minikube** cluster, in the `default` namespace as in the docs.
> Files: [lifecycle-events.yaml](lifecycle-events.yaml) (docs, **verbatim**). Not from the docs: [hook-behaviour.yaml](hook-behaviour.yaml).
> Concepts: [concepts/containers/container-lifecycle-hooks](../../../concepts/containers/container-lifecycle-hooks/).
>
> **Found:** the docs' preStop `nginx -s quit; while killall -0 nginx; do sleep 1; done` has no wait loop in practice.
> The current nginx image has **no `killall`**, so the loop condition fails at once. The graceful `nginx -s quit` still happens.

## Key ideas (read first)

| Hook | When | Blocks | If it fails |
|---|---|---|---|
| **postStart** | right after the container is created, **in parallel** with the entrypoint (no ordering guarantee) | the container is not `Running`/`Ready` until the hook returns | `FailedPostStartHook`, the container is **killed** and restarted per `restartPolicy` |
| **preStop** | before SIGTERM, only on *termination* (delete, liveness kill, preemption), **not** when the container completes by itself | termination waits for it, but it **counts against `terminationGracePeriodSeconds`** | `FailedPreStopHook` event, then SIGTERM anyway |

Handlers: `exec`, `httpGet`, `tcpSocket` (deprecated), and `sleep: {seconds: N}` (built in, no shell needed in the image).

---

## Step 0
```bash
cd tasks/configure-pod-container/attach-handler-lifecycle-event
```

## Lab 1 – The docs' Pod
```bash
kubectl apply -f lifecycle-events.yaml
kubectl get pod lifecycle-demo                       # Running
kubectl exec lifecycle-demo -- cat /usr/share/message
#   Hello from the postStart handler
kubectl exec lifecycle-demo -- sh -c 'command -v killall || echo "killall: not in the image"'
#   killall: not in the image
time kubectl delete pod lifecycle-demo
#   real 0m2.3s        <- nginx -s quit worked; the "wait until gone" loop didn't run
```
No `FailedPreStopHook` event: the `while` loop exits with status 0 when its condition command is missing.
A "working" loop (`while [ -e /run/nginx.pid ]; do sleep 1; done`) was tried too. It gives `FailedPreStopHook`: once nginx (PID 1)
exits, the container is gone and the hook's exec session is killed with it. Waiting inside the container for the main
process to exit can't succeed. `nginx -s quit` alone (or a `sleep` to let load balancers drain) is the useful part.

## Lab 2 – postStart blocks the status (not from the docs)
```bash
kubectl apply -f hook-behaviour.yaml
for i in 3 6 9 12; do sleep 3; echo "t+${i}s $(kubectl get pod poststart-blocks --no-headers | awk '{print $2,$3}')"; done
#   t+3s  0/1 ContainerCreating
#   t+6s  0/1 ContainerCreating
#   t+9s  0/1 ContainerCreating
#   t+12s 1/1 Running
kubectl exec poststart-blocks -- cat /tmp/log
#   entrypoint      04:28:14       <- the entrypoint was already running…
#   postStart begin 04:28:14
#   postStart end   04:28:24       <- …but the status only became Running now
```

## Lab 3 – A failing postStart kills the container (not from the docs)
```bash
kubectl get pod poststart-fails -o json | jq -c '{restarts:.status.containerStatuses[0].restartCount, waiting:.status.containerStatuses[0].state.waiting.reason}'
#   {"restarts":1,"waiting":"CrashLoopBackOff"}
kubectl get events --field-selector involvedObject.name=poststart-fails -o custom-columns=REASON:.reason,COUNT:.count,MSG:.message --no-headers
#   FailedPostStartHook   3   PostStartHook failed
#   Killing               3   FailedPostStartHook
#   BackOff               2   Back-off restarting failed container c …
```

## Lab 4 – preStop and the grace period (not from the docs)
```bash
for p in prestop-sleep prestop-too-long; do s=$(date +%s); kubectl delete pod $p >/dev/null; echo "$p: $(( $(date +%s)-s )) s"; done
#   prestop-sleep:    9 s     <- sleep action 8 s, then SIGTERM; the entrypoint traps TERM and exits
#   prestop-too-long: 8 s     <- hook wants 60 s, grace is 5 s: killed at 5 s + 2 s extra the kubelet grants
kubectl get events --field-selector involvedObject.name=prestop-too-long,reason=FailedPreStopHook
#   FailedPreStopHook   PreStopHook failed
```
In a first version, `prestop-sleep` ran a bare `sleep 3600` as PID 1. Deletion then took **31 s**: PID 1 ignores
SIGTERM by default, so after the 8 s hook the kubelet waited out the remaining grace before sending SIGKILL.
Hooks don't fix an app that ignores SIGTERM.

## Useful commands
```bash
kubectl explain pod.spec.containers.lifecycle
kubectl get events --field-selector reason=FailedPostStartHook
kubectl get events --field-selector reason=FailedPreStopHook
```

## Cleanup
```bash
./cleanup.sh
```
