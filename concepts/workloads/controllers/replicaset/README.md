# ReplicaSet – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **ReplicaSet** | Keeps a stable number of identical Pods running: `selector` + `replicas` + pod `template`. |
| **Use a Deployment instead** | Deployments manage ReplicaSets for you and add rolling updates. Use a bare ReplicaSet only if you need custom update orchestration, or no updates at all. |
| **Ownership** | Pods get an `ownerReferences` entry (`controller: true`) pointing to the RS. The RS finds Pods by **selector**. |
| **Acquisition** | Any Pod matching the selector **without a controller owner** is **adopted**, even bare Pods created outside the template. Too many → it deletes some. |
| **Selector** | Must match the template's labels. Overlapping selectors between controllers lead to fights. |
| **Delete** | Default: the RS and its Pods (background cascade). `--cascade=orphan`: Pods stay, and a new RS with the same selector **adopts** them (but doesn't update them to its template). |
| **Isolate a Pod** | Change its labels so it no longer matches. The RS replaces it, and the old Pod stays for debugging. |
| **Scale-down order** | Pending/unscheduled first, then by `controller.kubernetes.io/pod-deletion-cost` (lower goes first), then more replicas per node, then newer first. |
| **HPA target** | A ReplicaSet can be the `scaleTargetRef` of a HorizontalPodAutoscaler. |
| **Terminating Pods** | `.status.terminatingReplicas` (same feature as Deployments). |

## The demo app
The docs manifests are **verbatim**: [frontend.yaml](frontend.yaml) (RS `frontend`, 3 × `gb-frontend:v5`, selector `tier: frontend`), [pod-rs.yaml](pod-rs.yaml) (bare `pod1` and `pod2` labelled `tier: frontend`) and [hpa-rs.yaml](hpa-rs.yaml). Output excerpts, for reference: [pod-ownerreferences-output-excerpt.yaml](pod-ownerreferences-output-excerpt.yaml), [selector-excerpt.yaml](selector-excerpt.yaml).

---

## Lab 1 – Create (docs example)
```bash
cd concepts/workloads/controllers/replicaset
kubectl apply -f 00-namespace.yaml
kubectl apply -f frontend.yaml -n rs-demo
kubectl get rs frontend -n rs-demo               # DESIRED 3 CURRENT 3 READY 3 (gb-frontend is a big image - give it a minute)
kubectl describe rs frontend -n rs-demo | tail -5   # SuccessfulCreate x3
kubectl get pods -n rs-demo -o yaml | grep -A6 ownerReferences | head -8    # like pod-ownerreferences-output-excerpt.yaml
```

## Lab 2 – Non-template Pod acquisition (docs: created AFTER the RS)
```bash
kubectl apply -f pod-rs.yaml -n rs-demo          # pod/pod1 created, pod/pod2 created
kubectl get pods -n rs-demo                      # pod1/pod2 already gone (or Terminating)
```
They matched `tier: frontend`, the RS adopted them, saw 5 > 3, and deleted the extras.

## Lab 3 – Acquisition when the Pods exist FIRST
```bash
kubectl delete rs frontend -n rs-demo --cascade=orphan      # keep its 3 pods, now ownerless
kubectl apply -f pod-rs.yaml -n rs-demo                     # bare pod1, pod2 survive this time
kubectl apply -f frontend.yaml -n rs-demo
kubectl get pods -n rs-demo -o custom-columns=NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].name
#   frontend-…, frontend-…, frontend-…, pod1, pod2    ALL owned by "frontend"
#   -> then two of them are deleted to get back to 3
```
pod1/pod2 run **hello-app**, not the template's image. A ReplicaSet adopts by **label**, not by content. That's another reason to use Deployments with unique selectors.

## Lab 4 – Isolate a Pod for debugging
```bash
P=$(kubectl get pods -n rs-demo -l tier=frontend -o jsonpath='{.items[0].metadata.name}')
kubectl label pod $P -n rs-demo tier=debug --overwrite
kubectl get pods -n rs-demo -L tier          # $P now tier=debug (kept, no owner match); a NEW frontend-xxxxx replaced it
```

## Lab 5 – Choose which Pod goes first on scale-down
```bash
kubectl get pods -n rs-demo -l tier=frontend
V=$(kubectl get pods -n rs-demo -l tier=frontend -o jsonpath='{.items[0].metadata.name}')
kubectl annotate pod $V -n rs-demo controller.kubernetes.io/pod-deletion-cost=-100
kubectl scale rs frontend --replicas=2 -n rs-demo
kubectl get pods -n rs-demo -l tier=frontend      # $V is the one Terminating
```
Pods that are pending or not ready are removed before ready ones, regardless of cost.

## Lab 6 – ReplicaSet as an HPA target (docs)
```bash
kubectl apply -f hpa-rs.yaml -n rs-demo
kubectl get hpa -n rs-demo
#   frontend-scaler   ReplicaSet/frontend   cpu: <unknown>/50%   3   10   ...
kubectl get rs frontend -n rs-demo -w        # scaled back up to minReplicas 3 (we set 2 in Lab 5)
```
`<unknown>` CPU: metrics-server isn't installed (`minikube addons enable metrics-server`), and `gb-frontend` has no CPU request. See `../../autoscaling/horizontal-pod-autoscale`. The docs' imperative alternative is `kubectl autoscale rs frontend --max=10 --min=3 --cpu-percent=50`.

## Lab 7 – Delete
```bash
kubectl delete rs frontend -n rs-demo                       # RS and its pods (background cascade)
kubectl get pods -n rs-demo                                 # only the isolated "tier=debug" pod remains (not owned any more)
```

---

## Useful commands
```bash
kubectl get rs ; kubectl describe rs <name>
kubectl scale rs <name> --replicas=N
kubectl delete rs <name> --cascade=orphan
kubectl get pods -o custom-columns=NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].name
```

## Cleanup
```bash
./cleanup.sh
```
