# Kubernetes Object Management – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/

> **Warning from the docs:** manage each object with **only one** technique. Mixing techniques on the same object gives undefined behaviour.

## Key ideas (read first)

| Technique | Operates on | Recommended for | Writers | Learning curve | Commands |
|---|---|---|---|---|---|
| **Imperative commands** | Live objects | Development, one-off tasks | 1+ | Lowest | `kubectl create deployment …`, `scale`, `label`, `expose` |
| **Imperative object configuration** | Individual files | Production | 1 | Moderate | `kubectl create/replace/delete -f file` |
| **Declarative object configuration** | Directories of files | Production | 1+ | Highest | `kubectl diff -f dir/`, `kubectl apply -f dir/` (`-R` for sub-dirs) |

| Concept | Meaning |
|---|---|
| **No history** | Imperative commands leave no record of the previous configuration. Nothing to review, no audit trail, no template. |
| **replace** | Overwrites the whole live object with the file. **Changes made by anyone else are dropped.** Don't use it on objects the cluster also updates, such as a LoadBalancer Service's fields. |
| **apply** | Computes a **patch** from the file, the live object and the `last-applied-configuration` annotation. Changes by other writers to fields **not** in your file are kept. Fields that **are** in your file get set back to the file's value. |
| **create vs apply** | kubectl works out create, patch or delete per object, which is why `apply` works on directories. Deletion needs `--prune`. |

## The demo app
[nginx.yaml](nginx.yaml) and [redis.yaml](redis.yaml) are the files the docs' imperative commands name. [configs/](configs/) is the docs' `configs` directory: `web.yaml` holds a Deployment and a Service, and `backend/cache.yaml`, a ConfigMap, sits in a sub-directory so you can see what `-R` does.
The docs commands don't specify a namespace, so each command here adds `-n objmgmt-demo`.

---

## Step 1
```bash
cd concepts/overview/working-with-objects/object-management
kubectl apply -f 00-namespace.yaml
```

## Lab 1 – Imperative commands
```bash
kubectl create deployment nginx --image nginx -n objmgmt-demo     # docs example
kubectl scale deployment nginx --replicas=3 -n objmgmt-demo
kubectl get deploy nginx -n objmgmt-demo -o jsonpath='{.metadata.annotations}{"\n"}'
#   {"deployment.kubernetes.io/revision":"1"}   <- no last-applied-configuration, no file, no history
kubectl create deployment nginx2 --image nginx -n objmgmt-demo --dry-run=client -o yaml   # tip: make a template from a command
kubectl delete deployment nginx -n objmgmt-demo
```

## Lab 2 – Imperative object configuration (create / replace / delete)
```bash
kubectl create -f nginx.yaml -f redis.yaml -n objmgmt-demo
kubectl create -f nginx.yaml -n objmgmt-demo        # Error: AlreadyExists. create never updates
```
Another writer changes the live object. Here that's you on the command line; it could be an HPA or another tool:
```bash
kubectl label deploy nginx team=blue -n objmgmt-demo
kubectl scale deploy nginx --replicas=4 -n objmgmt-demo
kubectl replace -f nginx.yaml -n objmgmt-demo       # docs example
kubectl get deploy nginx -n objmgmt-demo -o jsonpath='{.metadata.labels} {.spec.replicas}{"\n"}'
#   {"app":"nginx"} 2      <- label team=blue LOST, replicas back to 2
```
This is the docs' warning: `replace` drops every change that isn't in the file.
```bash
kubectl delete -f nginx.yaml -f redis.yaml -n objmgmt-demo   # docs example
```

## Lab 3 – Declarative object configuration (diff + apply on a directory)
```bash
kubectl diff -f configs/ -n objmgmt-demo            # everything shows as new (+)
kubectl apply -f configs/ -n objmgmt-demo           # deployment.apps/web created, service/web created
kubectl get cm -n objmgmt-demo                      # cache-settings NOT created - sub-dirs need -R
kubectl diff -R -f configs/ -n objmgmt-demo
kubectl apply -R -f configs/ -n objmgmt-demo        # configmap/cache-settings created, web unchanged
```
Another writer changes the live object again:
```bash
kubectl label deploy web team=blue -n objmgmt-demo
kubectl scale deploy web --replicas=5 -n objmgmt-demo
kubectl diff -f configs/ -n objmgmt-demo | grep -E '^[-+] '
#   -  replicas: 5
#   +  replicas: 2       <- replicas IS in the file, so apply will reset it; the label is NOT in the diff
kubectl apply -f configs/ -n objmgmt-demo
kubectl get deploy web -n objmgmt-demo -o jsonpath='{.metadata.labels} {.spec.replicas}{"\n"}'
#   {"app":"web","app.kubernetes.io/part-of":"configs-demo","team":"blue"} 2
```
This is the docs' note: apply **keeps** other writers' changes (`team=blue`) because it sends a **patch**, not a replacement. A field you list in the file, `replicas`, belongs to the file. That's why manifests used with an HPA leave out `replicas`.
See what apply remembers:
```bash
kubectl get deploy web -n objmgmt-demo -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' | jq .metadata.labels
```

## Lab 4 – Deletes in declarative mode (`--prune`)
Run `apply` **without** `-R`, so `backend/cache.yaml` isn't in the set, and with prune limited by label:
```bash
kubectl apply -f configs/ -n objmgmt-demo --prune -l app.kubernetes.io/part-of=configs-demo --dry-run=server
#   deployment.apps/web unchanged
#   service/web unchanged
#   configmap/cache-settings pruned      <- labelled, live, but not in the files -> would be deleted
```
`--prune` is how "delete operations are automatically detected" in practice. Always scope it with `-l` or `--prune-allowlist`. kubectl warns that prune's defaults will change, and ApplySets (`--applyset`) are the newer mechanism.

## Lab 5 – Don't mix techniques
```bash
kubectl create -f redis.yaml -n objmgmt-demo
kubectl apply  -f redis.yaml -n objmgmt-demo
#   Warning: resource deployments/redis is missing the kubectl.kubernetes.io/last-applied-configuration
#   annotation ... The missing annotation will be patched automatically.
```
Without that annotation, apply can't tell which fields it used to own, so deleted fields may linger. That's the "undefined behaviour" in practice. Use `kubectl create --save-config` if you plan to switch to `apply` later.
Server-side apply (`kubectl apply --server-side`) tracks owners per field in `metadata.managedFields` instead:
```bash
kubectl apply --server-side -f configs/web.yaml -n objmgmt-demo
kubectl get deploy web -n objmgmt-demo --show-managed-fields -o yaml | grep -E 'manager:|operation:'
```

---

## Useful commands
```bash
kubectl diff -f <file|dir>                 # preview, exit code 1 if there are differences
kubectl apply -f <dir> -R                  # recursive
kubectl create ... --dry-run=client -o yaml > x.yaml    # imperative -> file
kubectl create -f x.yaml --save-config     # later apply will work cleanly
```

## Cleanup
```bash
./cleanup.sh
```
