# Owners and Dependents – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Owner / dependent** | A ReplicaSet **owns** its Pods, and the Pods are its **dependents**. A dependent points to its owner in `metadata.ownerReferences`. |
| **Owner reference** | `apiVersion`, `kind`, `name` **and `uid`**, plus optional `controller: true` (the managing controller) and `blockOwnerDeletion`. Controllers set these automatically (Deployment, ReplicaSet, DaemonSet, Job, CronJob, ReplicationController, Service→EndpointSlice). You can also set them by hand. |
| **vs labels** | Labels and selectors let a controller **find** its objects. Owner references say **who owns** an object, so that different parts of Kubernetes don't interfere with objects they don't control, and so garbage collection knows what to delete. |
| **blockOwnerDeletion** | In **foreground** deletion, the owner waits for dependents that have `blockOwnerDeletion: true`. Controllers set it to true. The `OwnerReferencesPermissionEnforcement` admission plugin allows setting it only if you can **delete** the owner. |
| **Namespace rules** | **No cross-namespace owners.** A namespaced dependent may have an owner in its own namespace or a cluster-scoped owner. A cluster-scoped dependent may only have cluster-scoped owners. Invalid references produce a warning Event with reason `OwnerRefInvalidNamespace`. |
| **Invalid ref outcomes** | Namespaced dependent → the reference is treated as **absent**, so the dependent gets **deleted**. Cluster-scoped dependent with a namespaced owner kind → **unresolvable**, so it is **never** garbage-collected. |
| **Cascading deletion** | `background` (default): the owner goes first and GC deletes the dependents afterwards. `foreground`: the owner gets a `foregroundDeletion` finalizer and waits for its blocking dependents. `orphan`: the owner gets the `orphan` finalizer, dependents are kept, and their ownerReferences are removed. |

## The demo app
[00-demo-app.yaml](00-demo-app.yaml) creates namespaces `owners-demo` and `owners-other`, plus Deployment `web` (2 nginx) and Service `web` in `owners-demo`.
[owner-ref.sh](owner-ref.sh) creates a ConfigMap, or a ClusterRole when the namespace is `-`, with an ownerReference to any existing object. It looks up the owner's UID for you.

---

## Step 1
```bash
cd concepts/overview/working-with-objects/owners-dependents
kubectl apply -f 00-demo-app.yaml
kubectl wait --for=condition=Available deploy/web -n owners-demo
```

## Lab 1 – Owner references set by controllers
```bash
kubectl get rs -n owners-demo -o json | jq -c '.items[0].metadata.ownerReferences'
#   [{"apiVersion":"apps/v1","blockOwnerDeletion":true,"controller":true,"kind":"Deployment","name":"web","uid":"a625…"}]
kubectl get pods -n owners-demo -l app=web -o json | jq -c '.items[0].metadata.ownerReferences'
#   [{... "kind":"ReplicaSet","name":"web-69c6f74b8b", "controller":true, "blockOwnerDeletion":true ...}]
```
That's a chain: Deployment → ReplicaSet → Pods. Both references have `blockOwnerDeletion: true` because a controller set them.

## Lab 2 – Labels **and** owner references (Service → EndpointSlice)
```bash
kubectl get endpointslices -n owners-demo -l kubernetes.io/service-name=web -o json | jq '.items[0].metadata | {labels, ownerReferences}'
```
Expected: the label `kubernetes.io/service-name: web` is how the control plane **finds** this Service's slices. The ownerReference `kind: Service, name: web` says **who owns** them. Delete the Service and its slices are garbage-collected.

## Lab 3 – Setting an owner reference by hand
```bash
kubectl create configmap parent -n owners-demo --from-literal=a=b
./owner-ref.sh configmap parent owners-demo child owners-demo
kubectl get cm child -n owners-demo -o jsonpath='{.metadata.ownerReferences}{"\n"}'
kubectl delete cm parent -n owners-demo
kubectl get cm child -n owners-demo           # NotFound - garbage collector removed the dependent
```

## Lab 4 – Cross-namespace and cluster-scoped mistakes
```bash
kubectl create configmap parent -n owners-demo --from-literal=a=b
./owner-ref.sh configmap parent owners-demo child-x owners-other   # namespaced dependent, owner in ANOTHER namespace
./owner-ref.sh configmap parent owners-demo child-cr -             # cluster-scoped dependent (ClusterRole), namespaced owner
sleep 10
kubectl get cm child-x -n owners-other        # NotFound   - ref treated as absent -> dependent deleted
kubectl get clusterrole child-cr              # still here - unresolvable owner -> never garbage-collected
kubectl get events -A --field-selector=reason=OwnerRefInvalidNamespace -o json \
  | jq -r '.items[] | "\(.involvedObject.kind)/\(.involvedObject.name): \(.message)"'
```
Expected (docs command):
```
ClusterRole/child-cr: ownerRef [v1/ConfigMap, namespace: , name: parent, uid: …] does not exist in namespace ""
ConfigMap/child-x:    ownerRef [v1/ConfigMap, namespace: owners-other, name: parent, uid: …] does not exist in namespace "owners-other"
```
Note that `child-x` was **deleted** even though its "owner" still exists, just in another namespace.
```bash
kubectl delete clusterrole child-cr
```

## Lab 5 – Cascading deletion and the finalizers it adds
Orphan deletes the owner and keeps the dependents:
```bash
kubectl delete deploy web -n owners-demo --cascade=orphan
kubectl get rs -n owners-demo -o json | jq -c '.items[] | {name: .metadata.name, owners: .metadata.ownerReferences}'
#   {"name":"web-69c6f74b8b","owners":null}      <- ReplicaSet survives, ownerReference removed
kubectl get pods -n owners-demo -l app=web       # still 2 pods (still owned by the RS)
```
Foreground means the owner waits, holding the `foregroundDeletion` finalizer:
```bash
kubectl delete rs -l app=web -n owners-demo --cascade=foreground --wait=false
kubectl get rs -l app=web -n owners-demo -o jsonpath='{.items[*].metadata.finalizers}{"\n"}'   # ["foregroundDeletion"] (run quickly)
kubectl get rs,pods -l app=web -n owners-demo -w                                              # pods go first, then the RS
```
Background is the default (`kubectl delete` without `--cascade`): the owner disappears at once and GC removes the dependents just after. For blocking dependents, see Lab 6 in [../finalizers](../finalizers/).

## Lab 6 – Who may set `blockOwnerDeletion`?
[01-limited-user-rbac.yaml](01-limited-user-rbac.yaml) defines ServiceAccount `limited`, which can create ConfigMaps but **can't delete** them, so it can't delete the owner.
```bash
kubectl apply -f 01-limited-user-rbac.yaml
kubectl create configmap parent -n owners-demo --from-literal=a=b --dry-run=client -o yaml | kubectl apply -f -
AS=system:serviceaccount:owners-demo:limited ./owner-ref.sh configmap parent owners-demo blocker owners-demo true
```
**On default minikube this succeeds** (`configmap/blocker created`), because `OwnerReferencesPermissionEnforcement` isn't in the enabled admission plugins:
```bash
minikube ssh -- "sudo grep -o 'enable-admission-plugins=[^ ]*' /etc/kubernetes/manifests/kube-apiserver.yaml"
#   NamespaceLifecycle,LimitRanger,ServiceAccount,...,ResourceQuota       (no OwnerReferencesPermissionEnforcement)
```
To see the protection the docs describe, restart minikube with the plugin. This restarts the API server.
```bash
minikube start --extra-config=apiserver.enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota,OwnerReferencesPermissionEnforcement
AS=system:serviceaccount:owners-demo:limited ./owner-ref.sh configmap parent owners-demo blocker2 owners-demo true
#   forbidden: cannot set blockOwnerDeletion if an ownerReference refers to a resource you can't set finalizers on   (expected; not run while writing this lab)
AS=system:serviceaccount:owners-demo:limited ./owner-ref.sh configmap parent owners-demo nonblocker owners-demo false   # allowed
```
Without the plugin, any user who can create a dependent could stall the owner's foreground deletion.

---

## Useful commands
```bash
kubectl get <kind> <name> -o jsonpath='{.metadata.ownerReferences}'
kubectl get pods -o custom-columns=NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind/.metadata.ownerReferences[0].name
kubectl delete <kind> <name> --cascade=background|foreground|orphan
kubectl get events -A --field-selector=reason=OwnerRefInvalidNamespace
```

## Cleanup
```bash
./cleanup.sh
```
