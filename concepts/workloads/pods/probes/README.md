# Liveness, Readiness, and Startup Probes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/probes/

## Key ideas (read first)

| Probe | Question | On failure |
|---|---|---|
| **startupProbe** | Has the app finished starting? | Keep waiting until `failureThreshold × periodSeconds`, then kill and restart. **Liveness and readiness don't run until it succeeds.** |
| **livenessProbe** | Is it alive, or deadlocked? | **Kill and restart** the container. |
| **readinessProbe** | Can it serve traffic now? | Remove from Service **endpoints**. **No restart.** It runs for the whole life of the container. |

| Concept | Meaning |
|---|---|
| **Mechanisms** | `httpGet` (2xx/3xx = success), `tcpSocket` (connection opens), `grpc` (gRPC Health Checking, port by **number** only), `exec` (exit code 0; runs a process inside the container, which is expensive at scale). |
| **Results** | Success, Failure, Unknown (the kubelet retries). |
| **Fields** | `initialDelaySeconds` (0), `periodSeconds` (10), `timeoutSeconds` (1), `successThreshold` (1; must be 1 for liveness/startup), `failureThreshold` (3), probe-level `terminationGracePeriodSeconds`. |
| **Probe-level grace** | When liveness/startup kills the container, the **probe's** `terminationGracePeriodSeconds` overrides the Pod's. |
| **HTTP details** | Custom headers (`httpHeaders`, an empty value removes a default header), redirects to another host → `ProbeWarning` event, only the first 10 KiB of the body is read. |
| **When to use** | Startup for slow starters (instead of a huge `initialDelaySeconds`). Liveness only if the app can get stuck without crashing. Readiness whenever traffic should wait or drain. |

## The demo app
The docs examples are **verbatim**: [probe-example.yaml](probe-example.yaml) (startup + liveness + readiness) and [grpc-liveness.yaml](grpc-liveness.yaml) (etcd with a gRPC liveness probe). Excerpts kept for reference: [probe-level-grace-excerpt.yaml](probe-level-grace-excerpt.yaml), [http-headers-excerpt.yaml](http-headers-excerpt.yaml), [http-headers-empty-excerpt.yaml](http-headers-empty-excerpt.yaml).
Runnable extras: [01-probe-example-runnable.yaml](01-probe-example-runnable.yaml) … [05-probe-level-grace.yaml](05-probe-level-grace.yaml).

---

## Step 1
```bash
cd concepts/workloads/pods/probes
kubectl apply -f 00-namespace.yaml
kubectl apply -f probe-example.yaml -f grpc-liveness.yaml -n probes-demo
kubectl apply -f 01-probe-example-runnable.yaml -f 02-liveness-http.yaml -f 03-readiness-exec.yaml -f 04-slow-start.yaml -f 05-probe-level-grace.yaml
sleep 60
kubectl get pods -n probes-demo -o custom-columns=NAME:.metadata.name,STARTED:.status.containerStatuses[0].started,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount
```
Expected after ~60s:
```
NAME                     STARTED   READY   RESTARTS
etcd-with-grpc           true      true    0       <- gRPC probe on 2379 passes
liveness-http            true      true    3       <- killed every ~10-15s (Lab 2)
probe-example            false     false   0       <- the docs example: never starts (Lab 1)
probe-example-runnable   true      true    0
probe-grace              false     false   3       <- killed with a 5s grace (Lab 5)
readiness-exec           true      true    0
slow-no-startup          true      true    1+      <- liveness killed it while starting (Lab 4)
slow-with-startup        true      true    0
```

## Lab 1 – The docs' probe-example, and why it never starts
```bash
kubectl logs probe-example -n probes-demo            # Paused
kubectl get events -n probes-demo --field-selector involvedObject.name=probe-example,reason=Unhealthy -o custom-columns=M:.message
#   Startup probe failed: Get "http://10.244.0.166:8080/healthz": dial tcp ...:8080: connect: connection refused
```
The docs' manifest runs agnhost **without arguments**, and agnhost's default subcommand is `pause`, so nothing listens on 8080. The startup probe allows 30 × 10s = 5 minutes, then the container is killed and restarted, over and over. Note that **liveness and readiness never ran**: they wait for startup.
[01-probe-example-runnable.yaml](01-probe-example-runnable.yaml) has the same probes with `args: ["netexec", "--http-port=8080"]`, so it starts and becomes Ready. (netexec answers 200 on any path, including `/ready`.)

## Lab 2 – Liveness: restart a stuck app
```bash
kubectl get events -n probes-demo --field-selector involvedObject.name=liveness-http -o custom-columns=R:.reason,M:.message | grep -E 'Unhealthy|Killing' | tail -2
#   Unhealthy  Liveness probe failed: HTTP probe failed with statuscode: 500
#   Killing    Container app failed liveness probe, will be restarted
```
`agnhost liveness` returns 200 for 10s, then 500, just like an app that deadlocks. The process is still running, but only the probe notices it's useless.

## Lab 3 – Readiness: stop traffic, don't restart
```bash
kubectl get endpointslice -n probes-demo -l kubernetes.io/service-name=ready-demo -o jsonpath='{.items[0].endpoints[0].conditions}{"\n"}'
#   {"ready":true,"serving":true,"terminating":false}
kubectl exec readiness-exec -n probes-demo -- rm /tmp/ready ; sleep 4
kubectl get endpointslice -n probes-demo -l kubernetes.io/service-name=ready-demo -o jsonpath='{.items[0].endpoints[0].conditions}{"\n"}'
#   {"ready":false,"serving":false,"terminating":false}      <- out of the Service
kubectl get pod readiness-exec -n probes-demo                 # 0/1 Running, RESTARTS 0
kubectl exec readiness-exec -n probes-demo -- touch /tmp/ready   # back in
```

## Lab 4 – Startup probe protects slow starters
Both pods sleep 25s before listening on 8080, and both have the same liveness probe (tcp, 3 × 3s = ~9s).
```bash
kubectl get events -n probes-demo --field-selector involvedObject.name=slow-no-startup -o custom-columns=R:.reason,M:.message | grep -E 'Unhealthy|Killing' | tail -2
#   Unhealthy  Liveness probe failed: dial tcp …:8080: connect: connection refused
#   Killing    Container app failed liveness probe, will be restarted       <- killed DURING start-up
kubectl get events -n probes-demo --field-selector involvedObject.name=slow-with-startup,reason=Unhealthy -o custom-columns=M:.message
#   Startup probe failed: ... (several times - harmless, it allows 30 × 2s)   <- then liveness takes over; never killed
```

## Lab 5 – Probe-level terminationGracePeriodSeconds
```bash
kubectl get events -n probes-demo --field-selector involvedObject.name=probe-grace -o custom-columns=TIME:.lastTimestamp,R:.reason,M:.message | grep -E 'Started|Unhealthy|Killing' | tail -3
#   13:03:54 Started    Container started
#   13:03:59 Unhealthy  Liveness probe failed: dial tcp ...:8080: connect: connection refused
#   13:03:59 Killing    Container test failed liveness probe, will be restarted
```
The Pod's grace period is **3600s** and the app ignores TERM. If the Pod value applied, the kill would take an hour. The probe's `terminationGracePeriodSeconds: 5` cuts it to 5s, which is why it cycles every ~15s.

## Lab 6 – gRPC probes (the docs' etcd example)
```bash
kubectl get pod etcd-with-grpc -n probes-demo -o jsonpath='{.spec.containers[0].livenessProbe}{"\n"}'     # {"grpc":{"port":2379,...}}
kubectl get pod etcd-with-grpc -n probes-demo                                                              # 1/1 Running, 0 restarts
```
etcd implements the standard `grpc.health.v1.Health` service. Unlike HTTP/TCP probes, the port must be a **number**, not a name.

---

## Useful commands
```bash
kubectl describe pod <p> | grep -E 'Liveness|Readiness|Startup'
kubectl get events --field-selector reason=Unhealthy
kubectl get pod <p> -o jsonpath='{.status.containerStatuses[0].started} {.status.containerStatuses[0].ready}'
```

## Cleanup
```bash
./cleanup.sh
```
