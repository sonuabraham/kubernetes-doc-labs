# Determine the Reason for Pod Failure – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-application/determine-reason-pod-failure/

> Runs on the default **minikube** cluster, in the `default` namespace as in the docs.
> Files: [termination.yaml](termination.yaml) (docs, **verbatim**). [termination-variants.yaml](termination-variants.yaml) holds the
> docs' `multi-container-pod` and `msg-path-demo` snippets made runnable, plus extra Pods for the policy and size limits.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Termination message** | Whatever the container writes to `terminationMessagePath` (default `/dev/termination-log`) ends up in `status.containerStatuses[].state.terminated.message` (or `lastState`, after a restart). Shown by `kubectl describe`, dashboards and alerting. |
| **`terminationMessagePolicy`** | `File` (default): the file only. `FallbackToLogsOnError`: if the file is empty **and** the exit code is non-zero, use the last log lines (≤ 2048 bytes / 80 lines). |
| **Size limits** | ≤ 4096 bytes per container, and 12 KiB per Pod split **equally** between all containers (init containers included). |
| **Path is immutable** | Set at creation time. |

---

## Step 0
```bash
cd tasks/debug/debug-application/determine-reason-pod-failure
```

## Lab 1 – Write and read a termination message (docs)
```bash
kubectl apply -f termination.yaml
kubectl get pod termination-demo             # Running → Completed → Running (restartPolicy Always restarts it)
kubectl get pod termination-demo -o json | jq -c '.status.containerStatuses[0].lastState.terminated|{exitCode, reason, message}'
#   {"exitCode":0,"reason":"Completed","message":"Sleep expired\n"}
kubectl get pod termination-demo -o go-template="{{range .status.containerStatuses}}{{.lastState.terminated.message}}{{end}}"
#   Sleep expired
```
The docs read `lastState` because the Pod restarts after exiting. For a Pod that stays terminated (`restartPolicy: Never`), the
message is in `state.terminated`, as in the labs below.

## Lab 2 – Which container failed? (the docs' multi-container template)
```bash
kubectl apply -f termination-variants.yaml
kubectl get pod multi-container-pod -o go-template='{{range .status.containerStatuses}}{{printf "%s:\n%s\n\n" .name .state.terminated.message}}{{end}}'
```
```
app:
shut down cleanly

db-migrate:
migration 0042 failed: column exists        <- exit code 3
```

## Lab 3 – Custom path and the two policies
```bash
for p in msg-path-demo fallback-demo file-policy-demo; do
  echo "$p: [$(kubectl get pod $p -o jsonpath='{.status.containerStatuses[0].state.terminated.message}')]"; done
```
| Pod | Setting | Message |
|---|---|---|
| msg-path-demo (docs) | `terminationMessagePath: /tmp/my-log` | `written to /tmp/my-log` |
| fallback-demo | `FallbackToLogsOnError`, nothing written to the file, exit 2 | `starting` / `panic: nil pointer dereference in handler.go:42` (the log tail) |
| file-policy-demo | same container, default `File` | *(empty)*. Only `kubectl logs` has the panic. |

`FallbackToLogsOnError` is a cheap win for apps you can't change: crash output becomes visible in `describe` and in Pod status.

## Lab 4 – Size limits
```bash
kubectl get pod big-message -o jsonpath='{.status.containerStatuses[0].state.terminated.message}' | wc -c
#   4096                      <- 10000 bytes written, truncated
kubectl get pod four-big-messages -o json | jq -r '.status.containerStatuses[] | "\(.name): \(.state.terminated.message|length) bytes"'
#   c1: 3072 bytes  c2: 3072 bytes  c3: 3072 bytes  c4: 3072 bytes     <- 12 KiB / 4 containers
```

## Useful commands
```bash
kubectl describe pod <p> | grep -A4 -E 'State|Last State'
kubectl get pod <p> -o jsonpath='{range .status.containerStatuses[*]}{.name}: {.state.terminated.exitCode} {.state.terminated.reason} {.state.terminated.message}{"\n"}{end}'
```

## Cleanup
```bash
./cleanup.sh
```
