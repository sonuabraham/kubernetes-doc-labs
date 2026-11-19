# StatefulSet Basics – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/

> Runs on the default **minikube**, namespace `default` (dynamic provisioning via the `standard` StorageClass). [web.yaml](web.yaml) and
> [web-parallel.yaml](web-parallel.yaml) are the docs examples **verbatim**. Everything happened as the page describes. The outputs below
> are from this cluster (v1.37).
>
> **Notes:**
> - The page keeps `kubectl get pods --watch -l app=nginx` running in a second terminal. The event lines below come from such a watch
>   (`--output-watch-events`, with time stamps added).
> - The interactive `kubectl run -i --tty --image busybox:1.28 dns-test --restart=Never --rm` + `nslookup` is shown as
>   `kubectl exec dns-test -- nslookup …` on a long-running `dns-test` Pod. Same image, same lookups.
> - v1.37 shows `updateStrategy.rollingUpdate.maxUnavailable: 1` in the spec by default (`{"maxUnavailable":1,"partition":0}`).
> - `kubectl rollout status sts/web` is a handy replacement for "watch until done". It prints `partitioned roll out complete: 3 new pods have been updated...`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Headless Service (`clusterIP: None`) + `serviceName` | gives each Pod a DNS name `web-N.nginx.default.svc.cluster.local` |
| Ordinal index | Pods are `web-0 … web-N-1`; created in order, each only after the previous is Running **and Ready** (`OrderedReady`) |
| Stable identity | hostname and DNS name survive a restart; the **IP doesn't** |
| `volumeClaimTemplates` | one PVC per Pod (`www-web-N`), re-attached to the same ordinal; **not** deleted on scale-down or StatefulSet delete |
| Scale down / rolling update | highest ordinal first |
| `partition: N` | only ordinals ≥ N get the new template (staging, canary, phased roll-out) |
| `OnDelete` | the template changes only when you delete a Pod yourself |
| `--cascade=orphan` | delete the StatefulSet but keep the Pods; a new StatefulSet with the same selector adopts them |
| `podManagementPolicy: Parallel` | create/delete all at once (updates are still ordered) |

## Lab 1 – Create, ordered creation
```bash
kubectl get pods --watch -l app=nginx          # terminal 2, keep it running
kubectl apply -f web.yaml                      # service/nginx created / statefulset.apps/web created
kubectl get service nginx                      # nginx   ClusterIP   None   <none>   80/TCP
kubectl get statefulset web                    # web   2/2
#   watch: 21:39:55 ADDED web-0 Pending … 21:39:56 web-0 1/1 Running
#          21:39:56 ADDED web-1 Pending … 21:39:57 web-1 1/1 Running      <- web-1 only after web-0 is Ready
```

## Lab 2 – Stable network identity
```bash
kubectl get pods -l app=nginx                  # web-0, web-1
for i in 0 1; do kubectl exec "web-$i" -- sh -c 'hostname'; done      # web-0 / web-1
kubectl run -i --tty --image busybox:1.28 dns-test --restart=Never --rm
  nslookup web-0.nginx       # Address 1: 10.244.0.37 web-0.nginx.default.svc.cluster.local
                             # (web-1.nginx → 10.244.0.38)
kubectl delete pod -l app=nginx
#   watch: web-0, web-1 Terminating → Completed → DELETED; web-0 Pending → Running, then web-1 Pending → Running (again in order)
for i in 0 1; do kubectl exec web-$i -- sh -c 'hostname'; done        # web-0 / web-1   (same names)
  nslookup web-0.nginx       # 10.244.0.40   <- new IP: use the DNS name, never the IP
```

## Lab 3 – Stable storage
```bash
kubectl get pvc -l app=nginx
#   www-web-0   Bound   pvc-ce60ebf5-…   1Gi   RWO   standard
#   www-web-1   Bound   pvc-125119fe-…   1Gi   RWO   standard
for i in 0 1; do kubectl exec "web-$i" -- sh -c 'echo "$(hostname)" > /usr/share/nginx/html/index.html'; done
for i in 0 1; do kubectl exec -i -t "web-$i" -- curl http://localhost/; done      # web-0 / web-1
kubectl delete pod -l app=nginx
for i in 0 1; do kubectl exec -i -t "web-$i" -- curl http://localhost/; done      # web-0 / web-1   <- same volume re-attached
```

## Lab 4 – Scaling
```bash
kubectl scale sts web --replicas=5
#   watch: web-2 Pending→Running, then web-3, then web-4 (one after the other)
kubectl patch sts web -p '{"spec":{"replicas":3}}'
#   watch: 21:40:27 web-4 Terminating → 21:40:28 DELETED, then web-3 Terminating → 21:40:29 DELETED   (highest first)
kubectl get pvc -l app=nginx
#   www-web-0 … www-web-4 all still Bound    <- PVCs of web-3 / web-4 are kept
```

## Lab 5 – Updating
```bash
# RollingUpdate (default)
kubectl get sts web -o jsonpath='{.spec.updateStrategy}'          # {"rollingUpdate":{"maxUnavailable":1,"partition":0},"type":"RollingUpdate"}
kubectl patch statefulset web --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value":"registry.k8s.io/nginx-slim:0.24"}]'
#   watch: web-2 Terminating→recreated→Running, then web-1, then web-0   (reverse order, one at a time)
for p in 0 1 2; do kubectl get pod "web-$p" --template '{{range $i, $c := .spec.containers}}{{$c.image}}{{end}}'; echo; done
#   registry.k8s.io/nginx-slim:0.24 (×3)

# Staging: partition 3 → nothing is updated
kubectl patch statefulset web -p '{"spec":{"updateStrategy":{"type":"RollingUpdate","rollingUpdate":{"partition":3}}}}'
kubectl patch statefulset web --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value":"registry.k8s.io/nginx-slim:0.21"}]'
kubectl delete pod web-2
kubectl get pod web-2 --template '{{range $i, $c := .spec.containers}}{{$c.image}}{{end}}'     # nginx-slim:0.24  (recreated with the OLD template)

# Canary: partition 2 → only web-2
kubectl patch statefulset web -p '{"spec":{"updateStrategy":{"type":"RollingUpdate","rollingUpdate":{"partition":2}}}}'
kubectl get pod web-2 --template '…'           # nginx-slim:0.21
kubectl delete pod web-1
kubectl get pod web-1 --template '…'           # nginx-slim:0.24  (below the partition: keeps the old template even when recreated)

# Phased: partition 0 → everyone
kubectl patch statefulset web -p '{"spec":{"updateStrategy":{"type":"RollingUpdate","rollingUpdate":{"partition":0}}}}'
#   web-0, web-1, web-2: nginx-slim:0.21     currentRevision = updateRevision = web-f99c84b4b

# OnDelete
kubectl patch statefulset web -p '{"spec":{"updateStrategy":{"type":"OnDelete", "rollingUpdate": null}}}'
kubectl get sts web -o jsonpath='{.spec.updateStrategy}'          # {"type":"OnDelete"}
```
NOT from the docs – OnDelete in action: patching the image to 0.24 leaves all Pods on 0.21. After `kubectl delete pod web-0`, web-0 alone
runs 0.24.

## Lab 6 – Deleting
```bash
# Non-cascading
kubectl delete statefulset web --cascade=orphan
kubectl get pods -l app=nginx                  # web-0, web-1, web-2 still Running (no ownerReferences any more)
kubectl delete pod web-0
kubectl get pods -l app=nginx                  # web-1, web-2   <- nobody recreates web-0
kubectl apply -f web.yaml                      # service/nginx unchanged / statefulset.apps/web created
#   watch: web-0 ADDED (recreated), web-2 Terminating → DELETED (web.yaml has replicas: 2), web-1 adopted without restart (AGE 36s)
for i in 0 1; do kubectl exec -i -t "web-$i" -- curl http://localhost/; done      # web-0 / web-1  (data still there)

# Cascading
kubectl delete statefulset web
#   watch: web-0 and web-1 Terminating in the same second (no ordering guarantee on delete)
kubectl delete service nginx
kubectl apply -f web.yaml
for i in 0 1; do kubectl exec -i -t "web-$i" -- curl http://localhost/; done      # web-0 / web-1  (PVCs survived the delete)
kubectl delete service nginx
kubectl delete statefulset web
```

## Lab 7 – Parallel Pod management
```bash
kubectl apply -f web-parallel.yaml
#   watch: 21:42:07 ADDED web-0 + ADDED web-1 (same second), both Running at 21:42:08
kubectl scale statefulset/web --replicas=5
#   watch: 21:42:09 ADDED web-2, web-3, web-4 at once; all Running at 21:42:10
```

## Cleanup
```bash
kubectl delete sts web
kubectl delete svc nginx
kubectl get pvc ; kubectl get pv                # 5 PVCs / 5 PVs (reclaim policy Delete), still there
kubectl delete pvc www-web-0 www-web-1 www-web-2 www-web-3 www-web-4
kubectl get pvc                                 # No resources found   (and the PVs disappear with them)
kubectl delete pod dns-test                     # only if you used the long-running variant
```
or `./cleanup.sh`.
