# Adopting Sidecar Containers – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/configuration/pod-sidecar-containers/

> The page is mostly prose: benefits, adoption checks, injection strategies. Its only commands are the two feature-gate checks. Every
> manifest here (`01`–`07`) is **NOT from the docs**. Each one demonstrates a claim the page makes. Runs on the default **minikube**
> (v1.37), namespace `default`.
>
> **Found:**
> - **The feature-gate check prints nothing on v1.37.** `SidecarContainers` isn't among the 256 `kubernetes_feature_enabled` series
>   (API server or kubelet). The gate went GA and was later removed, so the feature is simply always on. The page's
>   `stage="BETA"` sample dates from v1.29–1.32.
> - **`kubectl describe pod` never shows a container's `restartPolicy`** (checked with kubectl v1.35 and v1.37). So the page's way of
>   spotting a webhook that stripped the field doesn't work. Use `kubectl get pod … -o jsonpath='{.spec.initContainers[*].restartPolicy}'`.
> - **The "runtime feature detection design" has a race when built exactly as described** ([06](06-universal-injector.yaml)). The kubelet
>   treats the native sidecar's *first* run as started and launches the regular containers while it restarts. `OldWaySidecar` then
>   reads `first-run` and also acts as the sidecar. [07](07-universal-injector-wait.yaml) fixes this by polling the flag for up to 10 s.
> - A sidecar that ignores SIGTERM (a plain `sh` loop) delays Job completion by the whole grace period: 38 s instead of ~5 s, sidecar
>   exit code 137. Native sidecars don't *block* completion, but they still have to shut down.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Native sidecar | an entry in `initContainers` with `restartPolicy: Always`. It starts in init order, keeps running, and doesn't block the next init container |
| Start order | it's running *before* later init containers and the app start |
| Stop order | regular containers get SIGTERM first; sidecars only after they've exited (reverse order) |
| Jobs | the Pod completes when the regular containers finish; sidecars are restarted even with Pod `restartPolicy: Never` |
| Webhooks / old clients | a tool that rebuilds the Pod with an old API struct drops `restartPolicy` → the "sidecar" becomes a blocking init container and the Pod hangs in `Init:` |
| Universal injector | inject both a native and a legacy sidecar; at runtime one of them stands down |

## Lab 1 – Is the feature enabled? (docs commands)
```bash
kubectl get --raw /metrics | grep kubernetes_feature_enabled | grep SidecarContainers
#   (no output)  <- the gate no longer exists in v1.37; the feature is always on
kubectl get --raw /api/v1/nodes/minikube/proxy/metrics | grep kubernetes_feature_enabled | grep SidecarContainers
#   (no output)
kubectl get --raw /metrics | grep -c kubernetes_feature_enabled      # 256  (the metric itself works)
```

## Lab 2 – Start order ([01-start-order.yaml](01-start-order.yaml))
```bash
kubectl apply -f 01-start-order.yaml
kubectl logs sidecar-start-order -c migrate-db
#   up
#   init: sidecar is already running, migrating…      <- the regular init container sees the sidecar's file
kubectl get pod sidecar-start-order -o jsonpath='{range .status.initContainerStatuses[*]}{.name}: started={.started} {.state}{"\n"}{end}'
#   log-shipper: started=true {"running":{…}}
#   migrate-db:  started=false {"terminated":{…"reason":"Completed"…}}
kubectl get pod sidecar-start-order                   # READY 2/2  (the sidecar counts)

# webhook check – the docs suggest describe, but it doesn't print the field:
kubectl describe pod sidecar-start-order | grep -i 'restart policy'     # (nothing)
kubectl get pod sidecar-start-order -o jsonpath='{.spec.initContainers[*].restartPolicy}'   # Always
kubectl delete pod sidecar-start-order --now
```

## Lab 3 – Jobs ([02](02-job-native.yaml), [03](03-job-legacy.yaml), [05](05-job-sidecar-restarts.yaml))
```bash
kubectl apply -f 02-job-native.yaml -f 03-job-legacy.yaml -f 05-job-sidecar-restarts.yaml
kubectl get jobs                         # after ~1 min:
#   job-legacy-sidecar     Running    0/1   58s      <- never completes: the sidecar is a regular container
#   job-native-sidecar     Complete   1/1   38s      <- completes (38 s = 5 s work + 30 s grace for an sh loop that ignores SIGTERM)
#   job-sidecar-restarts   Complete   1/1   28s
kubectl get pods -l 'batch.kubernetes.io/job-name in (job-native-sidecar,job-legacy-sidecar)'
#   job-legacy-sidecar-…   1/2   NotReady    <- main Completed, sidecar still running
#   job-native-sidecar-…   0/2   Completed
kubectl get pod -l batch.kubernetes.io/job-name=job-native-sidecar \
  -o jsonpath='{.items[0].status.initContainerStatuses[0].state.terminated.exitCode}'       # 137 (SIGKILL after grace)
kubectl get pod -l batch.kubernetes.io/job-name=job-sidecar-restarts \
  -o jsonpath='{.items[0].spec.restartPolicy} restarts={.items[0].status.initContainerStatuses[0].restartCount}'
#   Never restarts=2     <- the Pod is "Never", yet the sidecar was restarted
kubectl delete job job-native-sidecar job-legacy-sidecar job-sidecar-restarts
```

## Lab 4 – Termination order ([04-termination-order.yaml](04-termination-order.yaml))
```bash
kubectl apply -f 04-termination-order.yaml
kubectl logs -f sidecar-termination -c app --timestamps &        # two followers, then delete
kubectl logs -f sidecar-termination -c sidecar --timestamps &
kubectl delete pod sidecar-termination
#   08:52:26.97  kubectl delete pod
#   08:52:27.50  [app]     app: got SIGTERM, draining 3 s
#   08:52:30.50  [app]     app: exit
#   08:52:30.65  [sidecar] sidecar: got SIGTERM        <- only after the app has exited
#   08:52:31.64  delete returned
```
(With snap kubectl, `kubectl logs -f … > file &` wrote nothing here. Pipe it through `| cat` or `| sed`, or keep it in the terminal.)

## Lab 5 – Universal injector, the page's design ([06](06-universal-injector.yaml)) and a fixed version ([07](07-universal-injector-wait.yaml))
```bash
kubectl apply -f 06-universal-injector.yaml
kubectl get pod universal-sidecar                       # 3/3 Running, RESTARTS 1  (the native sidecar's planned restart)
kubectl logs universal-sidecar -c native-sidecar --previous    # first run, exiting 0
kubectl logs universal-sidecar -c native-sidecar               # restarted: native sidecars supported, doing sidecar work
kubectl logs universal-sidecar -c old-way-sidecar
#   state=first-run
#   no native sidecar, acting as the sidecar        <- WRONG: the regular containers started before the restart → both sidecars active

kubectl apply -f 07-universal-injector-wait.yaml        # old-way-sidecar polls the flag (20 × 0.5 s) before deciding
kubectl logs universal-sidecar-wait -c old-way-sidecar
#   state=native
#   native sidecar is running, staying idle         <- correct
```
On a cluster without native sidecars the field is dropped, `native-sidecar` runs once as a normal init container, the flag stays
`first-run`, and 07's old-way sidecar takes over after 10 s. That path can't be shown on v1.37.

## Cleanup
```bash
./cleanup.sh
```
