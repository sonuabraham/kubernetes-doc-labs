# Pod Lifecycle – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/

> All YAML blocks from the page are here **verbatim** (file names below). Probes have their own lab ([../probes](../probes/)), conditions too ([../pod-condition](../pod-condition/)), and so do sidecars ([../sidecar-containers](../sidecar-containers/)).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Lifetime** | A Pod is scheduled **once** (uid) and stays on that node until it stops or is deleted. It's never rescheduled. A replacement is a **new** Pod (new uid). Its volumes share the Pod's lifetime. |
| **Phase** | `Pending` (accepted, not all containers started: scheduling or pulling), `Running` (bound, ≥1 container running/starting/restarting), `Succeeded` (all exited 0, won't restart), `Failed` (all terminated, ≥1 failed), `Unknown` (node unreachable). `CrashLoopBackOff` is **not** a phase. |
| **Container states** | `Waiting` (with a reason: ContainerCreating, ImagePullBackOff, CrashLoopBackOff…), `Running`, `Terminated` (exitCode, reason, start and finish times). |
| **restartPolicy (Pod)** | `Always` (any exit), `OnFailure` (non-zero exit), `Never`. Back-off 10s, 20s, 40s… capped at 5 min, and reset after 10 min of running fine. |
| **Container-level rules** | (`ContainerRestartRules`, beta, **on** here) A container can have its own `restartPolicy` and `restartPolicyRules` (exit code → `Restart`). An init container with `Never` fails the whole Pod. |
| **RestartAllContainers** | (beta, **on**) A rule action that restarts **all** containers in place (init containers run again) when a given exit code appears. |
| **Restart delay tuning** | kubelet `crashLoopBackOff.maxContainerRestartPeriod` (`KubeletCrashLoopBackOffMax`, beta). `ReduceDefaultCrashLoopBackOffDecay` (alpha, off). |
| **Readiness gates** | Extra conditions an **external controller** sets. Ready = all containers ready **and** all gates True. |
| **PodReadyToStartContainers** | (stable in v1.37) The sandbox and network are ready. |
| **Termination** | Delete → `deletionTimestamp` + grace period (30s by default) → removed from endpoints → preStop → stop signal (TERM) → after the grace period, KILL. `--grace-period=0 --force` removes the API object **without** waiting. Sidecars stop **after** the main containers. |
| **Pod GC** | The PodGC controller removes terminated Pods above `--terminated-pod-gc-threshold` (12500), orphans, and so on. See `../../../architecture/garbage-collection`. |

## The demo app
| File (verbatim from the docs) | Shows |
|---|---|
| [web-server.yaml](web-server.yaml) | `restartPolicy: Always` |
| [data-processor-job.yaml](data-processor-job.yaml) | a Job with `OnFailure`, exit 0 |
| [migration-task.yaml](migration-task.yaml) | `Never` + exit 1 → `Failed` |
| [app-with-sidecar.yaml](app-with-sidecar.yaml) | Pod `OnFailure` + sidecar `Always` |
| [on-failure-pod.yaml](on-failure-pod.yaml) | per-container `restartPolicy: Never` |
| [fail-pod-if-init-fails.yaml](fail-pod-if-init-fails.yaml) | init container `Never` → Pod fails |
| [restart-on-exit-codes.yaml](restart-on-exit-codes.yaml) | `restartPolicyRules` on exit code 42 |
| [restart-all-containers.yaml](restart-all-containers.yaml) | `RestartAllContainers` on exit 88 (the docs' `ml-worker`) |
| [kubelet-config-backoff-100s.yaml](kubelet-config-backoff-100s.yaml), [kubelet-config-backoff-2s.yaml](kubelet-config-backoff-2s.yaml) | KubeletConfiguration snippets (reference) |
| [readiness-gates-excerpt.yaml](readiness-gates-excerpt.yaml), [stop-signal-excerpt.yaml](stop-signal-excerpt.yaml) | excerpts (reference). The runnable versions are [01-readiness-gate.yaml](01-readiness-gate.yaml) and `../../../containers/container-lifecycle-hooks` |

---

## Step 1 – Run them all
```bash
cd concepts/workloads/pods/pod-lifecycle
kubectl apply -f 00-namespace.yaml
for f in web-server data-processor-job migration-task app-with-sidecar on-failure-pod fail-pod-if-init-fails restart-on-exit-codes restart-all-containers; do
  kubectl apply -f $f.yaml -n lifecycle-demo; done
sleep 90
kubectl get pods -n lifecycle-demo -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,REASON:.status.containerStatuses[*].state.*.reason,RESTARTS:.status.containerStatuses[*].restartCount,INIT-RESTARTS:.status.initContainerStatuses[*].restartCount
```
Expected:
```
NAME                     PHASE       REASON            RESTARTS   INIT-RESTARTS
app-with-sidecar         Running                       0          0
data-processor-xxxxx     Succeeded   Completed         0
fail-pod-if-init-fails   Failed      PodInitializing   0          0
migration-task           Failed      Error             0
ml-worker                Running                       1          1,1    <- after the watcher's exit 88
on-failure-pod           Running     Error             0,0
restart-on-exit-codes    Succeeded   Completed         0
web-server               Running                       0
```

## Lab 1 – Phases and container states
```bash
kubectl get pod migration-task -n lifecycle-demo -o jsonpath='{.status.phase} {.status.containerStatuses[0].state}{"\n"}'
#   Failed {"terminated":{"exitCode":1,"reason":"Error",...}}       <- Never + exit 1
kubectl get pod data-processor-xxxxx -n lifecycle-demo ...           # Succeeded/Completed - OnFailure + exit 0 = no restart
kubectl run crashy -n lifecycle-demo --image=busybox:1.36 -- sh -c 'exit 1'
kubectl get pod crashy -n lifecycle-demo -w        # Error -> CrashLoopBackOff -> ... while PHASE stays Running
kubectl get pod crashy -n lifecycle-demo -o jsonpath='{.status.phase} {.status.containerStatuses[0].state.waiting.reason}{"\n"}'   # Running CrashLoopBackOff
```

## Lab 2 – Per-container restart policy (ContainerRestartRules)
```bash
kubectl get pod on-failure-pod -n lifecycle-demo -o jsonpath='{range .status.containerStatuses[*]}{.name}: restarts={.restartCount} {.state}{"\n"}{end}'
#   on-failure-container: restarts=0 running         <- follows the Pod's OnFailure (still in its 1800s sleep)
#   try-once-container:   restarts=0 terminated exitCode 1   <- its own "Never" overrides the Pod's OnFailure
kubectl get pod fail-pod-if-init-fails -n lifecycle-demo -o jsonpath='{.status.phase} init-exit={.status.initContainerStatuses[0].state.terminated.exitCode}{"\n"}'
#   Failed init-exit=1           <- although the Pod's restartPolicy is Always
kubectl get pod restart-on-exit-codes -n lifecycle-demo -o jsonpath='{.status.phase}{"\n"}'
#   Succeeded                    <- exited 0, the rule only restarts on 42
```

## Lab 3 – RestartAllContainers (the docs' ml-worker)
```bash
kubectl get events -n lifecycle-demo --field-selector involvedObject.name=ml-worker -o custom-columns=R:.reason,M:.message | tail -6
kubectl get pod ml-worker -n lifecycle-demo -o jsonpath='{range .status.initContainerStatuses[*]}{.name} restarts={.restartCount}{"\n"}{end}{range .status.containerStatuses[*]}{.name} restarts={.restartCount}{"\n"}{end}'
#   setup-environment restarts=1    <- the init container ran AGAIN
#   watcher-sidecar   restarts=1
#   main-application  restarts=1    <- restarted in place: same Pod, same uid, same IP
```
Every 60s the watcher exits 88 and the whole Pod restarts in place. That's cheaper than deleting the Pod and rescheduling it.

## Lab 4 – Sidecar vs Pod restart policy
```bash
kubectl get pod app-with-sidecar -n lifecycle-demo -o jsonpath='{.spec.restartPolicy} sidecar={.spec.initContainers[0].restartPolicy}{"\n"}'   # OnFailure sidecar=Always
kubectl get pod app-with-sidecar -n lifecycle-demo -o jsonpath='{range .status.initContainerStatuses[*]}{.name} started={.started} ready={.ready}{"\n"}{end}'
#   logging-sidecar started=true ready=true     <- an init container that KEEPS running = a sidecar
```
(fluent-bit's image has no shell, so you can't crash it with `kubectl exec … kill`. [../sidecar-containers](../sidecar-containers/) has a sidecar you can crash and watch restart.)

## Lab 5 – Readiness gates
```bash
kubectl apply -f 01-readiness-gate.yaml ; sleep 10
kubectl get pod gated -n lifecycle-demo -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'
#   PodReadyToStartContainers=True Initialized=True Ready=False ContainersReady=True PodScheduled=True
#   <- containers are ready, the POD is not: the gate condition is missing
kubectl get pod gated -n lifecycle-demo -o wide        # READINESS GATES 0/1
kubectl patch pod gated -n lifecycle-demo --subresource=status --type=json \
  -p '[{"op":"add","path":"/status/conditions/-","value":{"type":"www.example.com/feature-1","status":"True"}}]'
kubectl get pod gated -n lifecycle-demo -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'
#   www.example.com/feature-1=True ... Ready=True
```
A load-balancer controller uses this to hold traffic until its own target is healthy.

## Lab 6 – Termination
```bash
kubectl delete pod web-server -n lifecycle-demo &                       # graceful: TERM, up to 30s
kubectl get pod web-server -n lifecycle-demo -o jsonpath='{.metadata.deletionTimestamp} grace={.metadata.deletionGracePeriodSeconds}{"\n"}'
kubectl apply -f web-server.yaml -n lifecycle-demo
kubectl delete pod web-server -n lifecycle-demo --grace-period=0 --force
#   Warning: Immediate deletion does not wait for confirmation that the running resource has been terminated.
```
Termination order with sidecars, preStop timing and stop signals are in `../sidecar-containers` and `../../../containers/container-lifecycle-hooks`.

## Lab 7 – Back-off tuning (kubelet config, optional)
```bash
minikube ssh -- "sudo grep -A1 crashLoopBackOff /var/lib/kubelet/config.yaml"     # (absent) = default, max 300s
```
To try the docs' snippet, add `crashLoopBackOff: {maxContainerRestartPeriod: "2s"}` to `/var/lib/kubelet/config.yaml`, then `sudo systemctl restart kubelet`. `crashy` now restarts every ~2s. Remove the setting afterwards.

---

## Useful commands
```bash
kubectl get pod <p> -o jsonpath='{.status.phase}'
kubectl get pod <p> -o jsonpath='{.status.containerStatuses[*].state}'
kubectl describe pod <p> | sed -n '/Conditions/,/Volumes/p'
kubectl get pods --field-selector status.phase=Failed
```

## Cleanup
```bash
./cleanup.sh
```
