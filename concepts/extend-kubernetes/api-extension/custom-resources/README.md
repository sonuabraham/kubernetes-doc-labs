# Custom Resources – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/

> The docs' example is **verbatim**: [shirt-resource-definition.yaml](shirt-resource-definition.yaml) (CRD `shirts.stable.example.com` with `selectableFields` and printer columns) and [shirt-resources.yaml](shirt-resources.yaml) (example1–3). The page's tables list many CRD features without examples, so the lab adds:
> - [01-backup-crd.yaml](01-backup-crd.yaml): a richer CRD with validation, defaults, a CEL rule, status + scale subresources, short name and category.
> - [02-backup.yaml](02-backup.yaml): a minimal Backup object.
> - [03-reader.yaml](03-reader.yaml) and [04-aggregate-to-view.yaml](04-aggregate-to-view.yaml): RBAC for the new types.
> - [etcd-get.sh](etcd-get.sh): reads raw values from etcd.
>
> The *custom controller* half is in `../../operator`. API aggregation, the other way to add resources, is in `../apiserver-aggregation`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Custom resource** | A new API endpoint (resource) for your own kind, added to a running cluster. kubectl, RBAC, watch and so on work as for Pods. |
| **Custom controller** | Data alone just gets stored. A controller that reconciles it makes it a **declarative API**. CR + controller = **Operator**. |
| **CRD vs. aggregated API** | **CRD**: no programming, the API server stores objects in etcd. **Aggregation**: your own API server behind the main one. More control (storage, protobuf, extra subresources) but code to run and maintain. |
| **When to use a CR** | Declarative, small, rarely-changing, human-edited objects with CRUD semantics. Not RPC-style operations, large data, high request rates, or application/user data. |
| **ConfigMap instead** | Use one when an existing file format is consumed by a Pod via a file or env, with rolling updates on change. Use a CR when you want kubectl/client libraries, watches, automation, and `spec`/`status`. |
| **CRD features** | OpenAPI validation + CEL rules, defaulting, multi-versioning (with conversion webhooks), status & scale subresources, printer columns, field selectors (`selectableFields`), finalizers, admission webhooks. |
| **Not with CRDs** | Custom storage, protobuf, strategic-merge-patch, extra subresources like `logs`/`exec`. These need an aggregated API. |
| **RBAC** | Built-in roles don't cover new types (except wildcard roles like cluster-admin). Grant them explicitly, e.g. with **aggregated ClusterRoles**. |

---

## Step 1
```bash
cd concepts/extend-kubernetes/api-extension/custom-resources
kubectl create ns cr-demo
kubectl apply -f shirt-resource-definition.yaml -f 01-backup-crd.yaml
kubectl wait --for=condition=Established crd/shirts.stable.example.com crd/backups.demo.example.com
kubectl apply -f shirt-resources.yaml -n cr-demo
```

## Lab 1 – A new API, instantly
```bash
kubectl get shirts -n cr-demo
#   NAME       COLOR   SIZE                      <- additionalPrinterColumns
#   example1   blue    S
#   example2   blue    M
#   example3   green   M
kubectl api-resources --api-group=stable.example.com           # shirts  stable.example.com/v1  true  Shirt
kubectl explain shirt.spec                                      # color <string>, size <string>  (served OpenAPI schema)
kubectl get --raw /apis/stable.example.com/v1/namespaces/cr-demo/shirts | jq '.items | length'      # 3  - plain REST
```

## Lab 2 – Field selectors (the page's example)
```bash
kubectl get shirts.stable.example.com -n cr-demo --field-selector spec.color=blue
#   example1   blue   S
#   example2   blue   M                          <- exactly the page's output
kubectl get shirts -n cr-demo --field-selector spec.size=M,spec.color=green      # example3
kubectl get shirts -n cr-demo --field-selector metadata.name=example3            # always supported
kubectl get shirts -n cr-demo --field-selector spec.fabric=cotton
#   Error: field label not supported: spec.fabric          <- only fields listed in selectableFields
```

## Lab 3 – Schema: pruning, validation, defaulting
Unknown fields:
```bash
printf 'apiVersion: stable.example.com/v1\nkind: Shirt\nmetadata: {name: typo}\nspec: {color: red, colour: red}\n' | kubectl apply -n cr-demo -f -
#   strict decoding error: unknown field "spec.colour"          <- kubectl asks for strict field validation by default
printf 'apiVersion: stable.example.com/v1\nkind: Shirt\nmetadata: {name: typo}\nspec: {color: red, colour: red}\n' | kubectl apply -n cr-demo --validate=ignore -f -
kubectl get shirt typo -n cr-demo -o jsonpath='{.spec}'       # {"color":"red"}   <- silently PRUNED
```
Defaulting: [02-backup.yaml](02-backup.yaml) only sets `database`.
```bash
kubectl apply -f 02-backup.yaml
kubectl get backup orders-db -n cr-demo -o jsonpath='{.spec}'
#   {"database":"orders","keepLast":3,"retainDays":7,"schedule":"0 3 * * *","tier":"bronze","workers":1}
kubectl get all -n cr-demo | grep backup                      # categories: [all] - it shows up in "get all"
```
Validation, measured with server dry-run:

| spec | Error |
|---|---|
| `{tier: gold}` | `spec.database: Required value` |
| `{database: x, tier: platinum}` | `Unsupported value: "platinum": supported values: "bronze", "silver", "gold"` |
| `{database: x, keepLast: 0}` | `spec.keepLast in body should be greater than or equal to 1` |
| `{database: x, keepLast: 10, retainDays: 2}` | `retainDays must be >= keepLast` (**CEL** `x-kubernetes-validations`) |
| `{database: x, workers: "two"}` | `spec.workers in body must be of type integer` |

## Lab 4 – Status and scale subresources
```bash
kubectl patch backup orders-db -n cr-demo --type=merge -p '{"status":{"phase":"Ignored"}}'
#   patched (no change)                       <- the main endpoint ignores .status
kubectl patch backup orders-db -n cr-demo --subresource=status --type=merge -p '{"status":{"phase":"Succeeded","lastRun":"2026-11-12T03:00:00Z"}}'
kubectl get backup orders-db -n cr-demo -o jsonpath='{.metadata.generation}'      # 1  - status writes don't bump generation
kubectl patch backup orders-db -n cr-demo --type=merge -p '{"spec":{"tier":"gold"}}'
kubectl get backup orders-db -n cr-demo -o jsonpath='{.metadata.generation}'      # 2  - spec writes do
kubectl scale backup orders-db -n cr-demo --replicas=4         # scale subresource -> .spec.workers
kubectl get --raw /apis/demo.example.com/v1/namespaces/cr-demo/backups/orders-db/scale | jq -c '{kind,spec,status}'
#   {"kind":"Scale","spec":{"replicas":4},"status":{"replicas":0}}       <- what HPA/PDB/kubectl scale talk to
kubectl get bk -n cr-demo
#   NAME        DB       TIER   WORKERS   PHASE       AGE
#   orders-db   orders   gold   4         Succeeded   3s
```
The split allows "users write spec, controller writes status" with separate RBAC on `backups` and `backups/status`.

## Lab 5 – Common API features for free
```bash
kubectl patch shirt example1 -n cr-demo --type=merge -p '{"spec":{"size":"L"}}'                               # merge-patch  OK
kubectl patch shirt example1 -n cr-demo --type=json -p '[{"op":"replace","path":"/spec/color","value":"navy"}]' # json-patch   OK
kubectl patch shirt example1 -n cr-demo --type=strategic -p '{"spec":{"size":"XL"}}'
#   error: application/strategic-merge-patch+json is not supported by stable.example.com/v1, Kind=Shirt
#          ... accepted media types include: application/json-patch+json, application/merge-patch+json, application/apply-patch+yaml
kubectl get shirts -n cr-demo --watch --output-watch-events    # terminal 2: ADDED / MODIFIED / DELETED events
```
Protobuf, with the admin client cert:
```bash
M=~/.minikube/profiles/minikube; C="--cacert $HOME/.minikube/ca.crt --cert $M/client.crt --key $M/client.key"
curl -s $C -H "Accept: application/vnd.kubernetes.protobuf" https://$(minikube ip):8443/apis/stable.example.com/v1/namespaces/cr-demo/shirts -o /dev/null -w '%{http_code}\n'   # 406
curl -s $C -H "Accept: application/vnd.kubernetes.protobuf" https://$(minikube ip):8443/api/v1/namespaces/cr-demo/configmaps -o /dev/null -w '%{http_code}\n'          # 200
```
Finalizers:
```bash
kubectl patch backup orders-db -n cr-demo --type=merge -p '{"metadata":{"finalizers":["demo.example.com/delete-snapshots"]}}'
kubectl delete backup orders-db -n cr-demo --wait=false
kubectl get backup orders-db -n cr-demo -o jsonpath='{.metadata.deletionTimestamp} {.metadata.finalizers}'
#   2026-11-12T09:16:51Z ["demo.example.com/delete-snapshots"]   <- blocked until "external cleanup" is done
kubectl patch backup orders-db -n cr-demo --type=json -p '[{"op":"remove","path":"/metadata/finalizers"}]'    # now it's gone
```

## Lab 6 – Storage
```bash
kubectl get crd backups.demo.example.com -o jsonpath='{.status.storedVersions}'     # ["v1"]
./etcd-get.sh /registry/stable.example.com/shirts/cr-demo/example3 | head -c 60
#   {"apiVersion":"stable.example.com/v1","kind":"Shirt","metada...     <- CRs are stored as JSON in the same etcd
./etcd-get.sh /registry/configmaps/cr-demo/kube-root-ca.crt | head -c 24 | od -c | head -2
#   k   8   s  \0 ... C o n f i g M a p                                    <- built-in types: protobuf
```
CRs take etcd space like ConfigMaps do, so don't use them as an application database.

## Lab 7 – RBAC for new types
```bash
kubectl apply -f 03-reader.yaml                 # SA "reader" + built-in ClusterRole "view" in cr-demo
AS=--as=system:serviceaccount:cr-demo:reader
kubectl auth can-i list pods -n cr-demo $AS                          # yes
kubectl auth can-i list shirts.stable.example.com -n cr-demo $AS     # no   <- "view" doesn't know about shirts
kubectl apply -f 04-aggregate-to-view.yaml      # ClusterRole labelled rbac.authorization.k8s.io/aggregate-to-view=true
kubectl auth can-i list shirts.stable.example.com -n cr-demo $AS     # yes
kubectl get clusterrole view -o json | jq -c '.rules[] | select(.apiGroups[0]|test("example"))'
#   {"apiGroups":["stable.example.com","demo.example.com"],"resources":["shirts","backups"],"verbs":["get","list","watch"]}
```

## Lab 8 – Deleting the CRD deletes the data
```bash
kubectl delete crd backups.demo.example.com
kubectl get backups -n cr-demo          # the server could not find the requested resource - all Backup objects are gone
```

---

## Useful commands
```bash
kubectl get crd ; kubectl api-resources --api-group=<group> ; kubectl explain <kind>.spec
kubectl get <plural>.<group> --field-selector <selectable-field>=<v>
kubectl patch <kind> <n> --subresource=status --type=merge -p '{"status":{...}}'
```

## Cleanup
```bash
./cleanup.sh        # namespace, both CRDs (and with them all their objects), the aggregated ClusterRole
```
