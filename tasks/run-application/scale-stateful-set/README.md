# Scale a StatefulSet – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/run-application/scale-stateful-set/

> Runs on the default **minikube** cluster, `default` namespace. The page has no manifest, so this lab brings its own (both **not from the docs**):
> [web-statefulset.yaml](web-statefulset.yaml) (nginx, 3 replicas, a PVC each, a readiness probe you can switch off with
> `touch /tmp/unready`) and [parallel-statefulset.yaml](parallel-statefulset.yaml) (the same with `podManagementPolicy: Parallel`).
> For a real replicated app, scale the MySQL StatefulSet from [run-replicated-stateful-application](../run-replicated-stateful-application/).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Ways | `kubectl scale`, `kubectl apply` (file's `replicas`), `kubectl edit`, `kubectl patch` |
| Order (`OrderedReady`, default) | up: 0,1,2… each after the previous is Ready; down: highest ordinal first, one at a time |
| Unhealthy Pod | with `OrderedReady`, scale-down **waits** until every Pod is Running and Ready |
| `Parallel` | no ordering and no waiting: scale-down goes ahead even with an unready Pod |
| PVCs | kept on scale-down (and re-attached on scale-up) unless `persistentVolumeClaimRetentionPolicy.whenScaled: Delete` |

---

## Lab 1 – Scale with kubectl (docs)
```bash
cd tasks/run-application/scale-stateful-set
kubectl apply -f web-statefulset.yaml
kubectl get statefulsets web                      # web   3/3
kubectl scale statefulsets web --replicas=5
kubectl get pods -l app.kubernetes.io/name=web
#   web-0..2 Running, web-3 ContainerCreating, (web-4 not yet)   <- one at a time
kubectl get events --field-selector involvedObject.name=web,reason=SuccessfulCreate -o custom-columns=MSG:.message | tail -3
#   Create Claim www-web-3 Pod web-3 in StatefulSet web success
#   Create Pod web-3 in StatefulSet web successful
#   Create Claim www-web-4 Pod web-4 in StatefulSet web success
```

## Lab 2 – Scale-down is blocked by an unhealthy Pod (docs "Troubleshooting")
```bash
kubectl exec web-1 -- touch /tmp/unready          # readiness fails → web-1 0/1
kubectl scale statefulsets web --replicas=2
kubectl get pods -l app.kubernetes.io/name=web    # (repeat for a while)
#   web-0 1/1  web-1 0/1  web-2 1/1  web-3 1/1  web-4 1/1     <- nothing is removed
kubectl exec web-1 -- rm /tmp/unready
kubectl get pods -l app.kubernetes.io/name=web    # web-4, web-3, web-2 go away; web-0, web-1 left
kubectl get pvc                                   # www-web-0 … www-web-4 all still there
```
Compare with `Parallel` (not from the docs):
```bash
kubectl apply -f parallel-statefulset.yaml
kubectl scale sts webp --replicas=4               # all 4 start together
kubectl exec webp-1 -- touch /tmp/unready
kubectl scale sts webp --replicas=1
kubectl get pods -l app.kubernetes.io/name=webp   # webp-0 only, removed at once
```

## Lab 3 – patch / apply, PVC reuse and retention (docs + extras)
```bash
kubectl patch statefulsets web -p '{"spec":{"replicas":4}}'
kubectl exec web-3 -- sh -c 'echo kept > /usr/share/nginx/html/index.html'
kubectl scale sts web --replicas=3; kubectl scale sts web --replicas=4
kubectl exec web-3 -- cat /usr/share/nginx/html/index.html     # kept    <- same PVC www-web-3 re-attached
kubectl patch sts web -p '{"spec":{"persistentVolumeClaimRetentionPolicy":{"whenScaled":"Delete","whenDeleted":"Retain"}}}'
kubectl scale sts web --replicas=2
kubectl get pvc                                   # www-web-0, www-web-1, www-web-4
#   www-web-2/3 deleted with their Pods; www-web-4 survives: its Pod was already gone before the policy was set
kubectl apply -f web-statefulset.yaml
kubectl get sts web                               # back to 3   <- the file's replicas wins
```
`kubectl edit statefulsets web` works the same way (interactive).

## Cleanup
```bash
./cleanup.sh
```
