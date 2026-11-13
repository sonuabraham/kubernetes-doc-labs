# Use Cascading Deletion in a Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/use-cascading-deletion/

> Runs on the default **minikube** cluster, namespace `default`, as in the docs. [deployment.yaml](deployment.yaml) is the sample Deployment the page points to (`application/deployment.yaml` from *Run a Stateless Application*), **verbatim**: `nginx-deployment`, 2 replicas. All six variants on the page are run (foreground, background and orphan, each via `kubectl` and via the API with `curl`). Recreate the Deployment before each one.

## Key ideas (read first)

| Policy | What happens to the owner | What happens to dependents |
|---|---|---|
| **Foreground** | Gets `deletionTimestamp` + finalizer `foregroundDeletion`, and stays **until all dependents with `blockOwnerDeletion` are gone** | Deleted first (ReplicaSet also goes foreground, then its Pods) |
| **Background** (default) | Deleted **immediately** | Garbage collector deletes them afterwards |
| **Orphan** | Gets finalizer `orphan` briefly, then is deleted | **Kept**; their `ownerReferences` are removed |

`ownerReferences` (Pod → ReplicaSet → Deployment) is what the garbage collector follows.

---

## Step 0 – the sample Deployment and its owner references
```bash
cd tasks/administer-cluster/use-cascading-deletion
kubectl apply -f deployment.yaml && kubectl rollout status deploy nginx-deployment
kubectl get pods -l app=nginx --output=yaml | grep -A6 ownerReferences
#   ownerReferences:
#   - apiVersion: apps/v1
#     blockOwnerDeletion: true
#     controller: true
#     kind: ReplicaSet
#     name: nginx-deployment-54fd4d6d4c
#     uid: 8dfcf8fb-...
```

## Lab 1 – Foreground cascading deletion
```bash
kubectl delete deployment nginx-deployment --cascade=foreground --wait=false
kubectl get deploy nginx-deployment -o jsonpath='{.metadata.finalizers} {.metadata.deletionTimestamp}{"\n"}'
#   ["foregroundDeletion"] 2026-11-13T21:32:36Z      <- owner still visible, marked for deletion
kubectl get rs -l app=nginx -o jsonpath='{.items[*].metadata.finalizers}'      # ["foregroundDeletion"]
kubectl get po -l app=nginx                                                     # Terminating ...
# a moment later: deployment, ReplicaSet and Pods are all gone
```
With the API (`kubectl proxy --port=8080` in another terminal):
```bash
curl -X DELETE localhost:8080/apis/apps/v1/namespaces/default/deployments/nginx-deployment \
    -d '{"kind":"DeleteOptions","apiVersion":"v1","propagationPolicy":"Foreground"}' \
    -H "Content-Type: application/json"
#   {"kind": "Deployment", ... "deletionTimestamp": "...", "finalizers": ["foregroundDeletion"], ...}
```

## Lab 2 – Background cascading deletion
```bash
kubectl apply -f deployment.yaml && kubectl rollout status deploy nginx-deployment
kubectl delete deployment nginx-deployment --cascade=background
#   deployment gone at once; its ReplicaSet and Pods are cleaned up right after by the garbage collector
curl -X DELETE localhost:8080/apis/apps/v1/namespaces/default/deployments/nginx-deployment \
    -d '{"kind":"DeleteOptions","apiVersion":"v1","propagationPolicy":"Background"}' \
    -H "Content-Type: application/json"
#   {"kind": "Status", "apiVersion": "v1", ..., "status": "Success", "details": {"name": "nginx-deployment", "group": "apps", "kind": "deployments", ...}}
#   right after: deployment NotFound, rs gone, pods Terminating
```

## Lab 3 – Delete the owner, orphan the dependents
```bash
kubectl apply -f deployment.yaml && kubectl rollout status deploy nginx-deployment
kubectl delete deployment nginx-deployment --cascade=orphan
#   (API: propagationPolicy "Orphan" -> response shows "finalizers": ["orphan"])
kubectl get rs -l app=nginx -o jsonpath='{.items[0].metadata.ownerReferences}'     # (empty) - no owner any more
kubectl get pods -l app=nginx
#   nginx-deployment-54fd4d6d4c-6ch9g   1/1   Running
#   nginx-deployment-54fd4d6d4c-8nxvp   1/1   Running                     <- still running
```
**Re-adoption (extra):** apply the same Deployment again. It finds the matching orphaned ReplicaSet (same Pod template hash) and adopts it, so no new Pods are created:
```bash
kubectl apply -f deployment.yaml
kubectl get rs -l app=nginx -o jsonpath='{range .items[*]}{.metadata.name} owner={.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}{end}'
#   nginx-deployment-54fd4d6d4c owner=Deployment/nginx-deployment
kubectl get pods -l app=nginx                # the same two Pods, same age
```

---

## Useful commands
```bash
kubectl delete <kind> <name> --cascade=foreground|background|orphan
kubectl get <obj> -o jsonpath='{.metadata.ownerReferences}{"\n"}{.metadata.finalizers}'
```

## Cleanup
```bash
kubectl delete -f deployment.yaml --ignore-not-found
```
