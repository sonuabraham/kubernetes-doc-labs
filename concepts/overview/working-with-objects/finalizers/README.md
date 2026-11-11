# Finalizers – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Finalizer** | A key in `metadata.finalizers`, such as `kubernetes.io/pv-protection`. It tells the API server to **wait** before really deleting the object, so a controller can clean up first. It holds no code, just a name, like an annotation. |
| **Delete with finalizers** | The API server sets `metadata.deletionTimestamp`, keeps the object, and responds that the delete was accepted. The object is removed only when `finalizers` is empty. |
| **Controller's job** | Watch for `deletionTimestamp`, do the cleanup, then remove **its own** key from `finalizers`. |
| **While deleting** | You can remove finalizers but **not add** them. You can't change `deletionTimestamp`. You **can't resurrect** the object: delete it and create a new one. |
| **Custom names** | Must be qualified: `example.com/name`. The API rejects unqualified custom names. |
| **Built-in examples** | `kubernetes.io/pv-protection`, `kubernetes.io/pvc-protection` (volumes in use), `batch.kubernetes.io/job-tracking` (Job pods), `foregroundDeletion` / `orphan` (garbage collection), `kubernetes` in a **Namespace's** `spec.finalizers` (empty the namespace first). |
| **Owner refs vs labels** | Controllers **track** their objects with labels. Garbage collection uses **owner references** to find what to delete. Finalizers on dependents can keep an owner in deletion for longer than expected. |
| **Stuck objects** | Don't just strip finalizers. Only remove one when you understand its purpose and have done its job some other way. |

## The demo app
The docs page has no manifests. Each lab file demonstrates one statement from the page, in namespace `finalizers-demo`.

---

## Step 1
```bash
cd concepts/overview/working-with-objects/finalizers
kubectl apply -f 00-namespace.yaml
```

## Lab 1 – A custom finalizer: you are the controller
```bash
kubectl apply -f 01-configmap-with-finalizer.yaml           # finalizers: [example.com/cleanup]
kubectl delete cm guarded -n finalizers-demo --wait=false -v=6 2>&1 | grep -E 'DELETE|deleted'
#   "Response" verb="DELETE" ... status="200 OK"
#   configmap "guarded" deleted                              <- kubectl says deleted ...
kubectl get cm guarded -n finalizers-demo -o json | jq -c '.metadata | {deletionTimestamp, finalizers}'
#   {"deletionTimestamp":"2026-…","finalizers":["example.com/cleanup"]}    <- ... but it's still here
```
The docs say the API returns `202 Accepted`. On v1.37 a ConfigMap delete returns **200** with the updated object. Either way the object isn't gone, and `deletionTimestamp` is the real signal.

Rules while the object is being deleted:
```bash
kubectl patch cm guarded -n finalizers-demo --type=json -p '[{"op":"add","path":"/metadata/finalizers/-","value":"example.com/another"}]'
#   Forbidden: no new finalizers can be added if the object is being deleted
kubectl patch cm guarded -n finalizers-demo --type=merge -p '{"data":{"important":"changed"}}'
#   patched - other fields can still change
kubectl apply -f 01-configmap-with-finalizer.yaml
#   Warning: Detected changes to resource guarded which is currently being deleted.  (it is NOT resurrected)
```
Now do the "cleanup" and remove the key:
```bash
kubectl patch cm guarded -n finalizers-demo --type=json -p '[{"op":"remove","path":"/metadata/finalizers/0"}]'
kubectl get cm guarded -n finalizers-demo          # NotFound - finalizers empty -> deleted
```

## Lab 2 – Names must be qualified
```bash
kubectl apply -f 02-unqualified-finalizer.yaml
#   metadata.finalizers[0]: Invalid value: "my-cleanup": name is neither a standard finalizer name nor is it fully qualified
```

## Lab 3 – The Namespace finalizer
```bash
kubectl get ns finalizers-demo -o jsonpath='{.spec.finalizers}{"\n"}'      # ["kubernetes"]
```
Namespaces keep their finalizer in `spec.finalizers`, not `metadata.finalizers`. The namespace controller removes it only after **everything inside** is deleted, which is why a namespace sits in `Terminating` while its contents go away (or forever, if something inside is stuck).

## Lab 4 – `kubernetes.io/pv-protection` (the docs' example)
```bash
kubectl apply -f 03-pv-protection.yaml
kubectl wait --for=condition=Ready pod/uses-volume -n finalizers-demo
kubectl get pv finalizers-demo-pv -o jsonpath='{.metadata.finalizers}{"\n"}'     # ["kubernetes.io/pv-protection"]
kubectl get pvc data -n finalizers-demo -o jsonpath='{.metadata.finalizers}{"\n"}'   # ["kubernetes.io/pvc-protection"]
kubectl delete pv finalizers-demo-pv --wait=false
kubectl delete pvc data -n finalizers-demo --wait=false
kubectl get pv finalizers-demo-pv ; kubectl get pvc -n finalizers-demo          # both STATUS Terminating
kubectl delete pod uses-volume -n finalizers-demo                               # stop using the volume
kubectl get pvc -n finalizers-demo ; kubectl get pv finalizers-demo-pv          # both gone
```
The finalizers kept the volume alive while a Pod used it. The data was protected against an accidental delete.

## Lab 5 – Labels, owner references and finalizers on Job pods
```bash
kubectl apply -f 04-job.yaml
kubectl get pods -n finalizers-demo -l batch.kubernetes.io/job-name=counter -o json \
  | jq '.items[0].metadata | {labels, finalizers, owner: .ownerReferences[0] | {kind, name, controller, blockOwnerDeletion}}'
```
Expected:
```
labels:      batch.kubernetes.io/job-name=counter, batch.kubernetes.io/controller-uid=…   <- how the Job TRACKS its pods
finalizers:  ["batch.kubernetes.io/job-tracking"]                                         <- result counted before the pod can vanish
owner:       {kind: Job, name: counter, controller: true, blockOwnerDeletion: true}       <- what GC uses to delete the pods with the Job
```
```bash
kubectl delete job counter -n finalizers-demo     # the owner reference (not the label) makes the pods go too
```

## Lab 6 – A finalizer on a dependent blocks the owner
```bash
kubectl apply -f 05-stuck-owner.yaml
UID_=$(kubectl get cm owner -n finalizers-demo -o jsonpath='{.metadata.uid}')
kubectl create secret generic dependent -n finalizers-demo --from-literal=k=v --dry-run=client -o json \
  | jq --arg uid "$UID_" '.metadata.finalizers=["example.com/keep"]
        | .metadata.ownerReferences=[{"apiVersion":"v1","kind":"ConfigMap","name":"owner","uid":$uid,"blockOwnerDeletion":true}]' \
  | kubectl apply -f -
kubectl delete cm owner -n finalizers-demo --cascade=foreground --wait=false
kubectl get cm owner -n finalizers-demo -o json | jq -c '.metadata | {deletionTimestamp, finalizers}'
#   {"deletionTimestamp":"…","finalizers":["foregroundDeletion"]}    <- owner waits for its dependents
kubectl get secret dependent -n finalizers-demo -o json | jq -c '.metadata | {deletionTimestamp, finalizers}'
#   {"deletionTimestamp":"…","finalizers":["example.com/keep"]}      <- dependent waits for "example.com/keep"
```
Troubleshoot as the docs suggest: check the **finalizers and owner references** on both objects. Once you know `example.com/keep`'s job is done, remove it:
```bash
kubectl patch secret dependent -n finalizers-demo --type=merge -p '{"metadata":{"finalizers":null}}'
kubectl get cm,secret -n finalizers-demo          # owner and dependent both gone
```
More on foreground and background deletion in [../owners-dependents](../owners-dependents/) and `../../../architecture/garbage-collection`.

---

## Useful commands
```bash
kubectl get <kind> <name> -o jsonpath='{.metadata.finalizers}{" "}{.metadata.deletionTimestamp}{"\n"}'
kubectl get <kind> -A -o json | jq -r '.items[] | select(.metadata.deletionTimestamp) | .metadata.namespace+"/"+.metadata.name'   # stuck objects
kubectl patch <kind> <name> --type=json -p '[{"op":"remove","path":"/metadata/finalizers/0"}]'   # last resort
```

## Cleanup
```bash
./cleanup.sh       # removes the lab's custom finalizers, the namespace and the PV
```
