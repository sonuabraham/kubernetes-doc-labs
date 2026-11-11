# Init Containers – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/init-containers/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Init container** | Runs **before** the app containers, **to completion**, **one at a time in order**. Each must succeed before the next one starts. |
| **Failure** | A failed init container is retried with back-off. If the Pod's `restartPolicy` is `Never`, the whole Pod **Fails**. (`Always` is treated as `OnFailure` for init containers.) |
| **vs app containers** | Same fields (resources, volumes, securityContext) but **no** `lifecycle`, `livenessProbe`, `readinessProbe` or `startupProbe`. |
| **vs sidecars** | A sidecar is an init container with `restartPolicy: Always`: it keeps running and supports probes. See [../sidecar-containers](../sidecar-containers/). |
| **Why** | Wait for dependencies, run setup with tools/secrets the app image shouldn't contain, or prepare files in a shared volume. |
| **Resources** | Effective Pod request = **max(largest init container request, sum of app container requests)**. The scheduler reserves that. |
| **Re-run** | Init containers run again if the Pod is restarted (for example the sandbox is recreated). Make them **idempotent**. |
| **Status** | `kubectl get` shows `Init:0/2`, `Init:Error`, `Init:CrashLoopBackOff`, then `PodInitializing`. |

## The demo app
The docs examples are **verbatim**: [myapp.yaml](myapp.yaml) (`myapp-pod` with `init-myservice` and `init-mydb`, which wait for DNS names) and [services.yaml](services.yaml) (Services `myservice` and `mydb`). Extra: [01-prepare-content.yaml](01-prepare-content.yaml), [02-effective-requests.yaml](02-effective-requests.yaml), [03-init-fails-never.yaml](03-init-fails-never.yaml).

---

## Lab 1 – The docs example: wait for Services
```bash
cd concepts/workloads/pods/init-containers
kubectl apply -f 00-namespace.yaml
kubectl apply -f myapp.yaml -n init-demo
kubectl get -f myapp.yaml -n init-demo                  # myapp-pod  0/1  Init:0/2
kubectl describe -f myapp.yaml -n init-demo | sed -n '/Init Containers/,/Conditions/p' | grep -E '^  [a-z]|State|Reason'
#   init-myservice: State Running              <- looping: nslookup myservice... fails
#   init-mydb:      State Waiting PodInitializing
#   myapp-container: State Waiting PodInitializing
kubectl logs myapp-pod -c init-myservice -n init-demo --tail=2     # waiting for myservice
kubectl apply -f services.yaml -n init-demo                        # service/myservice created, service/mydb created
kubectl get -f myapp.yaml -n init-demo -w                          # Init:1/2 -> PodInitializing -> Running 1/1
```

## Lab 2 – In order, one at a time, sharing a volume
```bash
kubectl apply -f 01-prepare-content.yaml ; sleep 15
kubectl exec web-with-content -n init-demo -- curl -s localhost
#   <h1>built at 12:57:00 by step-1</h1>
#   <p>decorated at 12:57:03 by step-2</p>
kubectl get pod web-with-content -n init-demo -o jsonpath='{range .status.initContainerStatuses[*]}{.name} {.state.terminated.startedAt} -> {.state.terminated.finishedAt}{"\n"}{end}'
#   step-1-fetch    12:57:00 -> 12:57:03
#   step-2-decorate 12:57:03 -> 12:57:03       <- started only after step-1 finished
```
The nginx image never needed `date` or a build tool. The init containers did that work and left the result in the emptyDir.

## Lab 3 – Effective resource request
```bash
kubectl apply -f 02-effective-requests.yaml ; sleep 10
kubectl describe node minikube | grep big-init
#   init-demo   big-init   2 (25%)   0 (0%)   64Mi (0%)   0 (0%)
#                          ^ max(init 2 CPU, app 300m+200m) = 2 CPU      ^ max(64Mi, 32+32=64Mi)
```
The 2 CPUs stay reserved for the Pod's whole life, even though `migrate` ran for 2 seconds. That's something to keep in mind when sizing init containers.

## Lab 4 – A failing init container with restartPolicy Never
```bash
kubectl apply -f 03-init-fails-never.yaml ; sleep 10
kubectl get pod init-fails-never -n init-demo       # 0/1  Init:Error   - Pod phase Failed, the app never started
kubectl logs init-fails-never -c check -n init-demo  # precondition not met
```
Remove `restartPolicy: Never` (default `Always`) and you get `Init:CrashLoopBackOff` instead: retried forever.

---

## Useful commands
```bash
kubectl get pod <p>                                  # Init:N/M
kubectl logs <p> -c <init-container>
kubectl get pod <p> -o jsonpath='{.status.initContainerStatuses}'
```

## Cleanup
```bash
./cleanup.sh
```
