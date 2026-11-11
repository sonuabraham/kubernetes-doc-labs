# Pod Conditions – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/pod-condition/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Condition** | An entry in `status.conditions[]`: `type`, `status` (`True`/`False`/`Unknown`), `lastProbeTime`, `lastTransitionTime`, `reason`, `message`, `observedGeneration`. The **phase** is one summary value, and conditions add the detail. |
| **Lifecycle conditions** (in order) | `PodScheduled` → `PodReadyToStartContainers` (sandbox + network ready) → `Initialized` (init containers done) → `ContainersReady` (all readiness probes pass) → `Ready` (receives Service traffic). |
| **Ready ≠ ContainersReady** | `Ready` additionally needs every **readiness gate** True. Otherwise `Ready=False, reason ReadinessGatesNotReady`. A missing gate condition counts as False. |
| **DisruptionTarget** | The Pod is about to be deleted by a disruption. Reasons: `PreemptionByScheduler`, `DeletionByTaintManager`, `EvictionByEvictionAPI`, `DeletionByPodGC`, `TerminationByKubelet`. Not set for self-inflicted failures such as exceeding limits. Job **podFailurePolicy** can match on it. |
| **Resize conditions** | `PodResizePending` (`Infeasible`: never fits this node; `Deferred`: might fit later, retried) and `PodResizeInProgress`. |
| **Custom conditions** | Written by controllers through `PATCH …/status`. The name must be a valid label key. |

## The demo app
[00-pods.yaml](00-pods.yaml) contains one pod per condition story: `slow`, `unschedulable`, `init-fails`, `not-ready`, `gated`, `evict-me` (has a finalizer so it stays visible after eviction), and `resize-me`. [conds.sh](conds.sh) prints `TYPE=STATUS(reason) @time`. The docs' two status excerpts are kept as [running-pod-conditions-excerpt.yaml](running-pod-conditions-excerpt.yaml) and [readiness-gates-excerpt.yaml](readiness-gates-excerpt.yaml) for reference.

---

## Lab 1 – The lifecycle conditions, one after another
```bash
cd concepts/workloads/pods/pod-condition
kubectl apply -f 00-pods.yaml ; sleep 25
./conds.sh slow
```
Expected:
```
PodScheduled=True()              @12:54:19
PodReadyToStartContainers=True() @12:54:19     <- sandbox + network
Initialized=True()               @12:54:27     <- +8s: init container slept 8s
ContainersReady=True()           @12:54:38     <- +11s: readiness probe initialDelaySeconds 10
Ready=True()                     @12:54:38
```
`kubectl get pod slow -n conditions-demo -o yaml` shows the same block as the docs' excerpt.

## Lab 2 – Where things get stuck
```bash
./conds.sh unschedulable     # PodScheduled=False(Unschedulable)            - nodeSelector matches no node
./conds.sh init-fails        # Initialized=False(ContainersNotInitialized)  - init container keeps failing
./conds.sh not-ready         # ContainersReady=False(ContainersNotReady), Ready=False(ContainersNotReady)
./conds.sh gated             # ContainersReady=True but Ready=False(ReadinessGatesNotReady)
```
The **first False condition** tells you where to look. That's quicker than reading all the events.

## Lab 3 – DisruptionTarget (Eviction API)
```bash
echo '{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"evict-me","namespace":"conditions-demo"}}' \
  | kubectl create --raw /api/v1/namespaces/conditions-demo/pods/evict-me/eviction -f -
./conds.sh evict-me | grep Disruption
#   DisruptionTarget=True(EvictionByEvictionAPI) @12:54:45
kubectl get pod evict-me -n conditions-demo -o jsonpath='{.status.phase} deleting-since={.metadata.deletionTimestamp}{"\n"}'
#   Succeeded deleting-since=…      <- still visible only because of our finalizer
```
`kubectl drain` uses the same Eviction API. `DeletionByTaintManager` appears when a node gets a `NoExecute` taint the Pod doesn't tolerate. **Don't try that on single-node minikube**: it would also evict CoreDNS and other system pods. Use the 2-node `arch-lab` profile (`../../../architecture/nodes`, Lab 6) instead.

## Lab 4 – Resize conditions
```bash
kubectl patch pod resize-me -n conditions-demo --subresource resize \
  -p '{"spec":{"containers":[{"name":"c","resources":{"requests":{"cpu":"7500m"},"limits":{"cpu":"7500m"}}}]}}'
./conds.sh resize-me | grep -i resize
#   PodResizePending=True(Deferred)
kubectl get pod resize-me -n conditions-demo -o jsonpath='{.status.conditions[?(@.type=="PodResizePending")].message}{"\n"}'
#   Node didn't have enough resource: cpu, requested: 7500, used: 850, capacity: 8000   <- fits capacity, not what's free: retry later
kubectl patch pod resize-me -n conditions-demo --subresource resize \
  -p '{"spec":{"containers":[{"name":"c","resources":{"requests":{"cpu":"64"},"limits":{"cpu":"64"}}}]}}'
#   Error from server (Forbidden): ... node didn't have enough allocatable resources: cpu, requested: 64000, allocatable: 8000
```
On v1.37 a resize that can **never** fit is rejected **at admission** (Forbidden), so you rarely see `Infeasible`. `Deferred` is what you'll meet.

## Lab 5 – Custom condition (readiness gate)
```bash
kubectl patch pod gated -n conditions-demo --subresource=status --type=json \
  -p '[{"op":"add","path":"/status/conditions/-","value":{"type":"www.example.com/feature-1","status":"True","reason":"LBReady"}}]'
./conds.sh gated              # www.example.com/feature-1=True(LBReady) ... Ready=True()
```

---

## Useful commands
```bash
kubectl get pod <p> -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
kubectl wait --for=condition=Ready pod/<p>
kubectl get pods -A -o json | jq -r '.items[] | select(.status.conditions[]? | .type=="DisruptionTarget") | .metadata.name'
```

## Cleanup
```bash
./cleanup.sh      # removes the finalizer from evict-me, deletes the namespace
```
