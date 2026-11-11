# StatefulSets – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **StatefulSet** | Like a Deployment, but every Pod has a **sticky identity**: ordinal name (`web-0`, `web-1`…), stable network ID and stable storage, kept across rescheduling. |
| **Use it when** | You need stable network IDs, stable per-Pod storage, ordered deployment/scaling, or ordered rolling updates. |
| **Limitations** | Storage comes from a provisioner (or pre-made PVs). Deleting or scaling down **doesn't delete volumes** by default. You must create the **headless Service** yourself. Deletion has no order guarantee (scale to 0 first). OrderedReady + a broken update may need a **forced rollback**. |
| **Stable network ID** | `<sts>-<ordinal>.<service>.<ns>.svc.cluster.local`, through the headless Service named in `serviceName`. |
| **Stable storage** | `volumeClaimTemplates` → one PVC per ordinal (`www-web-0`…), re-attached to the replacement Pod. |
| **Labels** | `statefulset.kubernetes.io/pod-name=web-1` and `apps.kubernetes.io/pod-index=1`. |
| **Ordinals** | `0..N-1`, or start at `.spec.ordinals.start` (StatefulSetStartOrdinal, GA). |
| **podManagementPolicy** | `OrderedReady` (default: create 0→N-1 one by one, each Running+Ready, + `minReadySeconds`; delete N-1→0) or `Parallel` (all at once). |
| **updateStrategy** | `RollingUpdate` (reverse ordinal order, one at a time, `partition` to stage, `maxUnavailable`: beta, **on**) or `OnDelete`. `Recreate` (alpha, **off** here). |
| **Revisions** | Every template is stored as a **ControllerRevision**. `kubectl rollout history/undo` works. `revisionHistoryLimit` (default 10). |
| **PVC retention** | `persistentVolumeClaimRetentionPolicy.whenDeleted / whenScaled`: `Retain` (default) or `Delete`. |

## The demo app
[statefulset.yaml](statefulset.yaml) is the docs manifest **verbatim**: headless Service `nginx` + StatefulSet `web` (3 × nginx-slim:0.24, `minReadySeconds: 10`, PVC template `www` with `storageClassName: my-storage-class`).
[00-prereqs.yaml](00-prereqs.yaml) creates namespace `sts-demo` and a StorageClass **named `my-storage-class`** (minikube's hostpath provisioner), so the docs manifest runs unchanged.
[01-parallel-startordinal.yaml](01-parallel-startordinal.yaml) is StatefulSet `para`: `Parallel`, `ordinals.start: 5`, `maxUnavailable: 2`, PVC retention `Delete`/`Delete`.
Excerpts kept: [revision-history-limit-excerpt.yaml](revision-history-limit-excerpt.yaml), [pvc-retention-excerpt.yaml](pvc-retention-excerpt.yaml).

---

## Lab 1 – Ordered creation (OrderedReady + minReadySeconds)
```bash
cd concepts/workloads/controllers/statefulset
kubectl apply -f 00-prereqs.yaml
kubectl apply -f statefulset.yaml -n sts-demo
kubectl get pods -n sts-demo -l app=nginx -w
#   +5s  web-0 Pending          <- PVC www-web-0 being provisioned
#   +25s web-0 Running
#   +35s web-0, web-1 Running   <- web-1 only after web-0 was Ready for 10s (minReadySeconds)
#   +45s web-0, web-1, web-2
kubectl get pvc -n sts-demo                   # www-web-0/1/2 Bound, STORAGECLASS my-storage-class
kubectl get pods -n sts-demo -l app=nginx -L apps.kubernetes.io/pod-index,statefulset.kubernetes.io/pod-name
```

## Lab 2 – Stable network identity
```bash
for i in 0 1 2; do kubectl exec web-$i -n sts-demo -- sh -c 'echo $(hostname) > /usr/share/nginx/html/index.html'; done
kubectl run dns -n sts-demo --image=busybox:1.36 --restart=Never -- sh -c 'nslookup nginx.sts-demo.svc.cluster.local; wget -qO- web-1.nginx'
kubectl logs dns -n sts-demo
#   3 Addresses (one per pod - headless Service, no ClusterIP)
#   web-1                      <- web-1.nginx always reaches pod web-1
```

## Lab 3 – Stable storage
```bash
kubectl delete pod web-1 -n sts-demo ; kubectl wait --for=condition=Ready pod/web-1 -n sts-demo --timeout=90s
kubectl exec web-1 -n sts-demo -- cat /usr/share/nginx/html/index.html     # web-1 - same name, same PVC, same data
```

## Lab 4 – Partitioned rolling update, revisions and rollback
```bash
kubectl patch sts web -n sts-demo -p '{"spec":{"updateStrategy":{"type":"RollingUpdate","rollingUpdate":{"partition":2}}}}'
kubectl patch sts web -n sts-demo --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"registry.k8s.io/nginx-slim:0.21"}]'
kubectl rollout status sts/web -n sts-demo           # partitioned roll out complete: 1 new pods have been updated...
kubectl get pods -n sts-demo -l app=nginx -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
#   web-0 0.24   web-1 0.24   web-2 0.21            <- only ordinals >= partition (a canary)
kubectl get controllerrevisions -n sts-demo -l app=nginx
kubectl get sts web -n sts-demo -o jsonpath='current={.status.currentRevision} update={.status.updateRevision}{"\n"}'
kubectl patch sts web -n sts-demo -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'    # roll the rest (2 -> 1 -> 0)
kubectl rollout status sts/web -n sts-demo
kubectl rollout history sts/web -n sts-demo
kubectl rollout undo sts/web -n sts-demo ; kubectl rollout status sts/web -n sts-demo     # back to 0.24 everywhere
```
Recreate isn't available on this cluster:
```bash
kubectl patch sts web -n sts-demo -p '{"spec":{"updateStrategy":{"type":"Recreate"}}}'
#   spec.updateStrategy: Invalid value: ... must be 'RollingUpdate' or 'OnDelete'     (StatefulSetRecreateStrategy alpha, off)
```

## Lab 5 – Scale down: reverse order, volumes kept
```bash
kubectl scale sts web --replicas=1 -n sts-demo
kubectl get pods -n sts-demo -l app=nginx -w         # web-2 goes first, then web-1
kubectl get pvc -n sts-demo                          # www-web-1, www-web-2 still Bound (default whenScaled: Retain)
kubectl scale sts web --replicas=3 -n sts-demo       # web-1/web-2 come back with their OLD data
```

## Lab 6 – Parallel, start ordinal, PVC auto-delete
```bash
kubectl apply -f 01-parallel-startordinal.yaml ; sleep 6
kubectl get pods -n sts-demo -l app=para             # para-5, para-6, para-7 all created at once (Parallel), numbered from 5
kubectl get pvc -n sts-demo | grep data              # data-para-5/6/7
kubectl scale sts para --replicas=1 -n sts-demo ; sleep 8
kubectl get pvc -n sts-demo | grep data              # only data-para-5 - whenScaled: Delete removed the others
kubectl delete sts para -n sts-demo ; sleep 5
kubectl get pvc -n sts-demo | grep data              # gone - whenDeleted: Delete
```

## Lab 7 – Forced rollback (why OrderedReady can get stuck)
```bash
kubectl set image sts/web nginx=registry.k8s.io/nginx-slim:does-not-exist -n sts-demo
kubectl get pods -n sts-demo -l app=nginx -w         # web-2 ImagePullBackOff - rollout waits FOREVER (it won't touch web-1)
kubectl rollout undo sts/web -n sts-demo             # revert the template ...
kubectl delete pod web-2 -n sts-demo                 # ... AND delete the broken pod: the controller won't replace a not-Ready pod by itself
```

---

## Useful commands
```bash
kubectl get sts,pods,pvc -l app=nginx
kubectl rollout status|history|undo sts/<name>
kubectl get controllerrevisions -l app=<label>
kubectl patch sts <name> -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":N}}}}'
```

## Cleanup
```bash
./cleanup.sh        # namespace (PVCs go with it) + the my-storage-class StorageClass
```
