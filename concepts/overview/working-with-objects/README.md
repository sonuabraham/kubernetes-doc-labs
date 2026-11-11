# Objects In Kubernetes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/working-with-objects/

> Sub-pages have their own labs: [object-management](object-management/), [names](names/), [labels](labels/), [namespaces](namespaces/), [annotations](annotations/), [field-selectors](field-selectors/), [finalizers](finalizers/), [owners-dependents](owners-dependents/), [common-labels](common-labels/), [storage-version](storage-version/).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Object** | A persistent entity in the Kubernetes API, and a **"record of intent"**. Once it's created, Kubernetes keeps working to make the cluster match it. Objects describe which apps run and where, the resources they get, and the policies (restart, upgrade, fault tolerance) around them. |
| **spec** | **Desired state.** You set it when you create the object. |
| **status** | **Current state.** Written by Kubernetes components, not by you. The control plane keeps driving status toward spec. |
| **Manifest** | A YAML (or JSON) file describing an object. `kubectl` converts it to JSON and sends it to the API server over HTTP. |
| **Required fields** | `apiVersion`, `kind`, `metadata` (`name`, plus optional `namespace`; the server adds `uid`), and `spec`. The format of `spec` is different for every kind. Look it up with `kubectl explain` or the API reference. |
| **Pod template** | Workload objects (Deployment, StatefulSet…) embed a Pod spec in `.spec.template`. Their controller creates Pods from it. |
| **Server-side field validation** | Since v1.25 (always available from v1.27), the API server detects **unknown** and **duplicate** fields. `kubectl --validate=strict` (default; `true`) fails the request. `warn` applies it and prints warnings. `ignore` (`false`) skips the check. |

## The demo app
The docs' manifest [deployment.yaml](deployment.yaml) is copied **verbatim**: `nginx-deployment`, 2 replicas, `nginx:1.14.2`. It has no namespace, so this lab applies it into `objects-demo`.

---

## Step 1 – Create the namespace
```bash
cd concepts/overview/working-with-objects
kubectl apply -f 00-namespace.yaml
```

## Lab 1 – Create an object from a manifest (the docs example)
```bash
kubectl apply -f deployment.yaml -n objects-demo
#   deployment.apps/nginx-deployment created
# the docs also show applying it straight from the URL:
#   kubectl apply -f https://k8s.io/examples/application/deployment.yaml -n objects-demo
kubectl get deploy,rs,pods -n objects-demo
```

## Lab 2 – spec (desired) vs status (actual)
```bash
kubectl get deploy nginx-deployment -n objects-demo -o json \
  | jq -c '{spec: .spec.replicas, status: (.status | {replicas, readyReplicas, availableReplicas, observedGeneration})}'
#   {"spec":2,"status":{"replicas":2,"readyReplicas":2,"availableReplicas":2,"observedGeneration":1}}
```
Make status differ from spec, then watch the control plane correct it, as in the docs' "an instance fails" example:
```bash
kubectl delete pod -n objects-demo -l app=nginx --wait=false
kubectl get deploy nginx-deployment -n objects-demo -w    # READY drops below 2/2, then returns to 2/2
```
Change the **spec**, and notice that `metadata.generation` (spec changes) and `status.observedGeneration` (what the controller has processed) move together:
```bash
kubectl scale deploy nginx-deployment -n objects-demo --replicas=3
kubectl get deploy nginx-deployment -n objects-demo -o jsonpath='{.metadata.generation} {.status.observedGeneration} {.status.readyReplicas}{"\n"}'
```
Try to set status yourself. `kubectl edit` a status field and the change is ignored, because status is a separate **subresource** (`/status`) owned by the controllers.

## Lab 3 – Required fields and the spec format
```bash
kubectl explain deployment                        # KIND, VERSION, FIELDS: apiVersion kind metadata spec status
kubectl explain deployment.spec --recursive | head -30
kubectl explain statefulset.spec.template         # the pod template inside a StatefulSet
kubectl apply -f 02-missing-required.yaml -n objects-demo
```
Expected for `02-missing-required.yaml`:
```
The Deployment "incomplete" is invalid:
* spec.selector: Required value
* spec.template.metadata.labels: Invalid value: null: `selector` does not match template `labels`
* spec.template.spec.containers: Required value
```

## Lab 4 – Server-side field validation
Unknown field. `spec.replica` is a typo for `replicas`:
```bash
for v in strict warn ignore; do echo "## $v"
  kubectl apply -f 01-unknown-field.yaml -n objects-demo --validate=$v --dry-run=server; done
```
Expected:
```
## strict
Error from server (BadRequest): ... strict decoding error: unknown field "spec.replica"
## warn
Warning: unknown field "spec.replica"
deployment.apps/typo-deployment created (server dry run)
## ignore
deployment.apps/typo-deployment created (server dry run)
```
With `ignore` the typo silently disappears, and the Deployment would get the default **1** replica. That is why `strict` is the default.

Duplicate field. kubectl turns YAML into JSON before sending it, so it already merges duplicate YAML keys. To see the **server** detect one, send raw JSON ([04-duplicate-field.json](04-duplicate-field.json) has `data` twice):
```bash
for v in Strict Warn Ignore; do echo "## $v"
  kubectl create --raw "/api/v1/namespaces/objects-demo/configmaps?fieldValidation=$v&dryRun=All" \
    -f 04-duplicate-field.json | head -c 120; echo; done
```
Expected: `Strict` → `strict decoding error: duplicate field "data"`. `Warn` → `Warning: duplicate field "data"` and the object is returned. `Ignore` → the object is returned with no warning.
`fieldValidation` is the API query parameter that `kubectl --validate` sets for you.

## Lab 5 – Manifests are just JSON on the wire
```bash
kubectl apply -f 03-deployment.json -n objects-demo --dry-run=server   # JSON manifests work too
kubectl apply -f deployment.yaml -n objects-demo -v=8 2>&1 | grep -E 'Request Body|PATCH|GET https' | head -5
kubectl get deploy nginx-deployment -n objects-demo -o yaml | head -20   # server-added: uid, resourceVersion, generation, creationTimestamp, managedFields
```

---

## Useful commands
```bash
kubectl explain <kind>[.field...]          # spec format for any object
kubectl get <kind> <name> -o yaml          # full object: metadata, spec, status
kubectl apply -f x.yaml --dry-run=server   # full validation + admission, nothing stored
kubectl api-resources                      # every kind the cluster knows
```

## Cleanup
```bash
./cleanup.sh
```
