# Delete a StatefulSet – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/run-application/delete-stateful-set/

> Runs on the default **minikube** cluster, `default` namespace. The page uses placeholders only. This lab brings
> [myapp-statefulset.yaml](myapp-statefulset.yaml) (**not from the docs**): a headless Service + 3-replica StatefulSet `myapp` with PVCs,
> labelled `app.kubernetes.io/name=MyApp` so the page's commands work as written.
>
> **Found:** "the StatefulSet scales down to 0" is misleading. With `kubectl delete` (background cascading deletion), the garbage collector
> deletes all Pods **at once**, not in reverse ordinal order. If your app needs ordered shutdown, run `kubectl scale --replicas=0` first.
> The `sleep $grace` step isn't needed to protect data: the `kubernetes.io/pvc-protection` finalizer keeps a PVC until no Pod uses it.

## Key ideas (read first)

| Action | Pods | PVCs | Headless Service |
|---|---|---|---|
| `kubectl delete sts` / `-f file` | deleted (all together) | **kept** | kept with `delete sts`; deleted with `-f file` (it is in the file) |
| `--cascade=orphan` | kept, `ownerReferences` removed | kept | as above |
| re-create the StatefulSet | orphans are **adopted** | re-used (same names) | |
| `persistentVolumeClaimRetentionPolicy.whenDeleted: Delete` | deleted | deleted too (StatefulSet becomes their owner) | |

---

## Lab 1 – Delete by name (docs)
```bash
cd tasks/run-application/delete-stateful-set
kubectl apply -f myapp-statefulset.yaml
kubectl delete statefulsets myapp
kubectl get pods -l app.kubernetes.io/name=MyApp
#   myapp-0 Terminating   myapp-1 Terminating   myapp-2 Terminating     <- all at once
kubectl get svc,pvc -l app.kubernetes.io/name=MyApp
#   service/myapp                         <- "delete the headless service separately"
#   persistentvolumeclaim/www-myapp-0..2  Bound
```

## Lab 2 – `--cascade=orphan` (docs + adoption)
```bash
kubectl apply -f myapp-statefulset.yaml           # PVCs from Lab 1 are re-used
kubectl delete -f myapp-statefulset.yaml --cascade=orphan     # deletes the Service and the StatefulSet
kubectl get pods -l app.kubernetes.io/name=MyApp  # myapp-0..2 still Running
kubectl get pod myapp-0 -o jsonpath='{.metadata.ownerReferences}'     # (empty)
kubectl apply -f myapp-statefulset.yaml
kubectl get pod myapp-0 -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}'
#   StatefulSet/myapp      <- adopted by label; Pods weren't restarted (same AGE)
kubectl delete -f myapp-statefulset.yaml --cascade=orphan
kubectl delete pods -l app.kubernetes.io/name=MyApp           # the docs' follow-up
```

## Lab 3 – Complete deletion (docs)
```bash
kubectl apply -f myapp-statefulset.yaml
grace=$(kubectl get pods myapp-0 --template '{{.spec.terminationGracePeriodSeconds}}')   # 10
kubectl delete statefulset -l app.kubernetes.io/name=MyApp
sleep $grace
kubectl delete pvc -l app.kubernetes.io/name=MyApp
```
Without the `sleep` (not from the docs):
```bash
kubectl delete pvc -l app.kubernetes.io/name=MyApp --wait=false
kubectl get pvc -l app.kubernetes.io/name=MyApp          # STATUS Terminating
kubectl get pvc www-myapp-0 -o jsonpath='{.metadata.finalizers}'   # ["kubernetes.io/pvc-protection"]
#   … removed once the Pods are gone; then the dynamic PVs are deleted (reclaimPolicy Delete)
```

## Lab 4 – Let the StatefulSet delete its PVCs (not from the docs)
```bash
kubectl patch --local -f myapp-statefulset.yaml -o yaml \
  -p '{"spec":{"persistentVolumeClaimRetentionPolicy":{"whenDeleted":"Delete"}}}' | kubectl apply -f -
kubectl get pvc www-myapp-0 -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}'
#   StatefulSet/myapp
kubectl delete sts myapp
kubectl get pvc -l app.kubernetes.io/name=MyApp          # No resources found
```

Force deletion of stuck Pods: see [force-delete-stateful-set-pod](../force-delete-stateful-set-pod/).

## Cleanup
```bash
./cleanup.sh
```
