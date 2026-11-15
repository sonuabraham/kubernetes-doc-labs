# Share Process Namespace between Containers in a Pod – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/share-process-namespace/

> Runs on the default **minikube** cluster, in the `default` namespace as in the docs.
> Files: [share-process-namespace.yaml](share-process-namespace.yaml) (docs, **verbatim**).
> Not from the docs: [visibility-demo.yaml](visibility-demo.yaml).
>
> **Found:** the page says signalling another container's process "requires the `SYS_PTRACE` capability". Measured:
> **signals work without it**, since root already has `CAP_KILL`. `SYS_PTRACE` is what lets you read the **environment** and
> **root filesystem** of a process running as a *different user*.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`shareProcessNamespace: true`** | All containers of the Pod share one PID namespace. PID 1 is the sandbox's `/pause`, not your app. |
| **Visible to every container** | the process list and `/proc/<pid>/cmdline` (so never pass passwords as arguments) |
| **Needs permission** | signals (same uid or `CAP_KILL`), and `/proc/<pid>/environ` and `/proc/<pid>/root` (same uid, or `CAP_SYS_PTRACE` for other uids) |
| **Uses** | debugging shell-less images (`kubectl debug --target` does something similar for a single container), sidecars that signal the app (e.g. config reload with `kill -HUP`) |
| **Gotcha** | `kill -HUP 1` now goes to `/pause`, not your app. Images that need to be PID 1 (systemd) won't work. |

---

## Step 0
```bash
cd tasks/configure-pod-container/share-process-namespace
kubectl apply -f share-process-namespace.yaml -f visibility-demo.yaml
kubectl wait --for=condition=Ready pod/nginx pod/visibility-demo pod/nginx-private
```

## Lab 1 – One process list for the whole Pod (docs)
```bash
kubectl exec -it nginx -c shell -- /bin/sh     # or non-interactively:
kubectl exec nginx -c shell -- ps ax
```
```
PID   USER     TIME  COMMAND
    1 65535     0:00 /pause                                   <- the sandbox, PID 1 (runs as 65535 nowadays)
    7 root      0:00 nginx: master process nginx -g daemon off;
   35 root      0:00 sleep 3600                               <- the shell container
   41 101       0:00 nginx: worker process                    <- ×8 (worker_processes auto, 8 CPUs)
   49 root      0:00 ps ax
```
Compare a Pod **without** sharing:
```bash
kubectl exec nginx-private -c shell -- ps ax
#   1 root  sleep 3600      <- its own PID 1, nginx invisible
#   7 root  ps ax
```

## Lab 2 – Signal and look into nginx (docs)
```bash
kubectl exec nginx -c shell -- sh -c 'kill -HUP 7; sleep 1; ps ax | grep worker'
#   73 101  nginx: worker process      <- new PIDs: the master re-read its config and replaced the workers
kubectl exec nginx -c shell -- head -3 /proc/7/root/etc/nginx/nginx.conf
#   (blank line)
#   user  nginx;
#   worker_processes  auto;
kubectl exec nginx -c shell -- sh -c 'kill -HUP 1; echo rc=$?'
#   rc=0        <- went to /pause (which ignores it), not to nginx
```

## Lab 3 – What exactly needs SYS_PTRACE (not from the docs)
`visibility-demo`: `app` runs as **uid 1000** with `DB_PASSWORD` in its environment. `shell` is root with default caps,
and `shell-ptrace` is root + `SYS_PTRACE`.
```bash
A=$(kubectl exec visibility-demo -c shell -- sh -c "ps ax | awk '\$2==\"1000\" {print \$1; exit}'")   # 7
for c in shell shell-ptrace; do echo "== from $c"; kubectl exec visibility-demo -c $c -- sh -c "
  cat /proc/$A/cmdline | tr '\0' ' '; echo
  tr '\0' '\n' < /proc/$A/environ | grep DB_ || echo 'environ: denied'
  ls /proc/$A/root/bin >/dev/null && echo 'root fs: ok' || echo 'root fs: denied'
  kill -STOP $A && kill -CONT $A && echo 'signal: ok'" 2>/dev/null; done
```
| | `shell` (no SYS_PTRACE) | `shell-ptrace` |
|---|---|---|
| `/proc/7/cmdline` | `sleep 3600` | `sleep 3600` |
| `/proc/7/environ` | **denied** | `DB_PASSWORD=s3cr3t` |
| `/proc/7/root/…` | **denied** | ok |
| `kill -STOP/-CONT 7` | ok | ok |

For processes with the **same** uid (root → root nginx master), both work without `SYS_PTRACE`. Reading
`/proc/<worker>/root` (uid 101) fails with `Permission denied` from the docs-like Pod *without* the capability.
nginx itself is a poor test for the environ check: it overwrites its own environment area with its process title.

## Useful commands
```bash
kubectl get pod <p> -o jsonpath='{.spec.shareProcessNamespace}'
kubectl exec <p> -c <c> -- grep CapEff /proc/self/status
```

## Cleanup
```bash
./cleanup.sh
```
