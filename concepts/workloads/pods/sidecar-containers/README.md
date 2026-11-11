# Sidecar Containers – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Sidecar** | A secondary container in the same Pod that **keeps running** alongside the app: logging, proxies, data sync. Stable via the `SidecarContainers` feature. |
| **How** | Put it in **`initContainers`** with **`restartPolicy: Always`**. |
| **Start-up** | Started in init-container order, but it **doesn't block** waiting to finish. The next container starts once the sidecar is *started*: running, or its **startupProbe** succeeded. |
| **Independent lifecycle** | It can restart without restarting the app. It supports `lifecycle` hooks and liveness/readiness/startup probes. Its **readiness counts** towards Pod readiness. |
| **Termination** | The kubelet stops sidecars **after** the main containers have stopped, in **reverse** order of declaration. If the app uses up the grace period, sidecars get TERM then KILL with no time left. |
| **Jobs** | A running sidecar **doesn't prevent** a Job from completing once the main container finishes. |
| **Resources** | Sidecars run alongside the app, so their requests are **added**: effective = max(largest regular init request, sum of sidecars + sum of app containers). |
| **vs init containers** | Init containers run to completion and have no probes. Sidecars keep running and support probes. |

## The demo app
The docs examples are **verbatim**: [deployment-sidecar.yaml](deployment-sidecar.yaml) (`myapp` writes to `/opt/logs.txt`, sidecar `logshipper` runs `tail -F`) and [job-sidecar.yaml](job-sidecar.yaml) (`myjob` with the same sidecar). Extra: [01-order.yaml](01-order.yaml) (two sidecars + app, with timestamps and a startupProbe) and [02-sidecar-requests.yaml](02-sidecar-requests.yaml).

---

## Step 1
```bash
cd concepts/workloads/pods/sidecar-containers
kubectl apply -f 00-namespace.yaml
kubectl apply -f deployment-sidecar.yaml -f job-sidecar.yaml -n sidecar-demo
```

## Lab 1 – The docs' Deployment: a log shipper
```bash
kubectl get pods -n sidecar-demo -l app=myapp             # 2/2 Running - the sidecar counts as a running container
kubectl logs deploy/myapp -c logshipper -n sidecar-demo --tail=3      # logging, logging, ...  (tail -F of the app's file)
kubectl get pod -n sidecar-demo -l app=myapp -o jsonpath='{.items[0].spec.initContainers[0].restartPolicy}{"\n"}'   # Always
```

## Lab 2 – The docs' Job: the sidecar doesn't block completion
```bash
kubectl get job myjob -n sidecar-demo -w
#   myjob   Running    0/1   ...
#   myjob   Complete   1/1   41s        <- completes although logshipper never exits on its own
kubectl get pod -n sidecar-demo -l job-name=myjob -o jsonpath='{.items[0].status.initContainerStatuses[0].state.terminated.exitCode}{"\n"}'
#   137                                 <- the sidecar was SIGKILLed after the grace period
```
Why 41s and not ~1s? The main container finishes at once, then the kubelet stops the sidecar. `tail` runs as PID 1 and has no TERM handler, so it ignores TERM, and the kubelet waits the full 30s grace period before SIGKILL. Good sidecars handle SIGTERM.

## Lab 3 – Start-up order and the startupProbe
```bash
kubectl apply -f 01-order.yaml
kubectl wait --for=condition=Ready pod/ordered -n sidecar-demo --timeout=60s
for c in sidecar-a sidecar-b app; do kubectl logs ordered -c $c -n sidecar-demo; done | sort
#   12:58:50 sidecar-a started
#   12:58:58 sidecar-a ready          <- startupProbe (test -f /tmp/up) passes after 8s
#   12:58:59 app started              <- only now do sidecar-b and the app start
#   12:58:59 sidecar-b started
```

## Lab 4 – A sidecar restarts on its own
```bash
kubectl exec ordered -c sidecar-b -n sidecar-demo -- kill 1 ; sleep 5
kubectl get pod ordered -n sidecar-demo -o jsonpath='{range .status.initContainerStatuses[*]}{.name} restarts={.restartCount}  {end}app restarts={.status.containerStatuses[0].restartCount}{"\n"}'
#   sidecar-a restarts=0  sidecar-b restarts=1  app restarts=0      <- independent lifecycle
```

## Lab 5 – Shutdown order
```bash
for c in sidecar-a sidecar-b app; do kubectl logs -f ordered -c $c -n sidecar-demo --timestamps & done
kubectl delete pod ordered -n sidecar-demo
```
Expected order, per the docs: **app** gets TERM first (it sleeps 3s on TERM), then **sidecar-b**, then **sidecar-a** (reverse order). Each prints `… got TERM` with its time. The kubelet's `Killing` events only have 1-second resolution, so they can't separate the steps here:
```bash
kubectl get events -n sidecar-demo --field-selector involvedObject.name=ordered,reason=Killing -o custom-columns=TIME:.lastTimestamp,MSG:.message
```

## Lab 6 – Requests add up
```bash
kubectl apply -f 02-sidecar-requests.yaml ; sleep 10
kubectl describe node minikube | grep sidecar-requests
#   sidecar-demo   sidecar-requests   1 (12%)  ...
#   = max( setup init 1 CPU , proxy sidecar 300m + app 200m = 500m )
```
Raise the sidecar to 900m and it becomes 1.1 CPU (900m + 200m > 1). Sidecars run the whole time, so they count with the app.

---

## Useful commands
```bash
kubectl get pod <p> -o jsonpath='{range .spec.initContainers[*]}{.name}={.restartPolicy} {end}'
kubectl logs <p> -c <sidecar>
kubectl get pod <p> -o jsonpath='{.status.initContainerStatuses}'
```

## Cleanup
```bash
./cleanup.sh
```
