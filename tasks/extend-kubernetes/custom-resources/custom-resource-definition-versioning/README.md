# Versions in CustomResourceDefinitions – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definition-versioning/

> Runs on the default **minikube** cluster (v1.37), `default` namespace. Files from the docs, **verbatim** (the `apiextensions.k8s.io/v1` tabs only):
> [01-my-versioned-crontab.yaml](01-my-versioned-crontab.yaml), [02-deprecated-versions.yaml](02-deprecated-versions.yaml),
> [03-version-removal.yaml](03-version-removal.yaml), [04-my-versioned-crontab-with-conversion.yaml](04-my-versioned-crontab-with-conversion.yaml),
> [05-conversion-url.yaml](05-conversion-url.yaml), [06-conversion-service-port.yaml](06-conversion-service-port.yaml),
> [07-conversionreviewversions.yaml](07-conversionreviewversions.yaml) (snippets), [08](08-conversionreview-request.yaml)/[09](09-conversionreview-response.yaml)/[10](10-conversionreview-failure.yaml)
> (ConversionReview examples), [11-crd-plus-storageversionmigration.yaml](11-crd-plus-storageversionmigration.yaml).
>
> Not from the docs: [conversion_webhook.py](conversion_webhook.py) (a real conversion webhook, `hostPort` ↔ `host`+`port`, logs every
> review), [webhook-deployment.yaml](webhook-deployment.yaml) + [setup-webhook.sh](setup-webhook.sh) (deploys it as the docs'
> `example-conversion-webhook-server` on `/crdconvert` and fills in `caBundle`), [version-priority.yaml](version-priority.yaml),
> `*-fixed.yaml`, [crontabs-v1beta1.yaml](crontabs-v1beta1.yaml), [12-storageversionmigration.yaml](12-storageversionmigration.yaml).
>
> **Found:**
> 1. `02`, `03` and `11` don't apply as written: `schema: ...` is a literal string (`cannot restore struct from: string`), and `11` has a bare `...` line
>    (invalid YAML). The `-fixed` files / `12-…` fill them in.
> 2. **One unconvertible object breaks the whole list.** With a failing conversion, `kubectl get crontabs` (v1) returns
>    `StorageReadError: … corrupt object`, and `kubectl delete` via v1 fails too. The object can still be read and **deleted through the storage
>    version** (`crontabs.v1beta1.example.com`). This goes further than the page's "can disrupt read and write access".
> 3. With the webhook **down**, lists at v1 still work (served from the API server's watch cache, already converted), but single GETs and v1
>    creates fail; v1beta1 (the storage version) keeps working completely.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `versions[]` | each with `served`, exactly one `storage: true`, its own `schema`; optional `deprecated` + `deprecationWarning` |
| Conversion `None` | only `apiVersion` changes; for identical schemas |
| Conversion `Webhook` | API server POSTs a `ConversionReview` (one or more objects) whenever the requested version ≠ stored version |
| Preferred version | highest by Kubernetes version sorting (GA > beta > alpha, bigger numbers first, non-matching names last, alphabetical) |
| `status.storedVersions` | every version that has ever been the storage version; a version can't be removed from `spec.versions` while listed |
| Upgrading storage | change `storage`, then rewrite all objects (StorageVersionMigration or read+write), then `storedVersions` shrinks |

---

## Lab 1 – Two versions, `None` conversion (docs)
```bash
cd tasks/extend-kubernetes/custom-resources/custom-resource-definition-versioning
ET=../../../../concepts/extend-kubernetes/api-extension/custom-resources/etcd-get.sh     # read raw etcd values
kubectl apply -f 01-my-versioned-crontab.yaml
kubectl get --raw /apis/example.com | jq -c '{versions: [.versions[].version], preferred: .preferredVersion.version}'
#   {"versions":["v1","v1beta1"],"preferred":"v1"}
printf 'apiVersion: example.com/v1beta1\nkind: CronTab\nmetadata: {name: beta-object}\nhost: localhost\nport: "1234"\n' | kubectl apply -f -
kubectl get ct beta-object -o jsonpath='{.apiVersion}'                         # example.com/v1        <- preferred version
kubectl get crontabs.v1beta1.example.com beta-object -o jsonpath='{.apiVersion}'   # example.com/v1beta1
kubectl get crd crontabs.example.com -o jsonpath='{.status.storedVersions}'    # ["v1beta1"]
$ET /registry/example.com/crontabs/default/beta-object | grep -o '"apiVersion":"[^"]*"' | head -1     # "apiVersion":"example.com/v1beta1"
```

## Lab 2 – Version priority (docs list, tested)
```bash
kubectl apply -f version-priority.yaml        # the docs' ten names, in shuffled order
kubectl get --raw /apis/prio.example.com | jq -r '"preferred: " + .preferredVersion.version, "order: " + ([.versions[].version] | join(" "))'
#   preferred: v10
#   order: v10 v2 v1 v11beta2 v10beta3 v3beta1 v12alpha1 v11alpha2 foo1 foo10        <- exactly the docs' list
```

## Lab 3 – Deprecation and removal (docs, fixed schemas)
```bash
kubectl apply -f 02-deprecated-versions.yaml        # The request is invalid: … "schema":"…" … cannot restore struct from: string
kubectl delete ct beta-object
kubectl apply -f 02-deprecated-versions-fixed.yaml
kubectl get crontabs.v1alpha1.example.com
#   Warning: example.com/v1alpha1 CronTab is deprecated; see http://example.com/v1alpha1-v1 for instructions to migrate to example.com/v1 CronTab
kubectl get crontabs.v1beta1.example.com
#   Warning: example.com/v1beta1 CronTab is deprecated; use example.com/v1 CronTab          <- default text
kubectl get crd crontabs.example.com -o jsonpath='{.status.storedVersions}'    # ["v1beta1","v1"]   (storage moved to v1)
kubectl apply -f 03-version-removal-fixed.yaml        # v1beta1 served: false
kubectl get crontabs.v1beta1.example.com              # NotFound … the server could not find the requested resource
# try to drop v1beta1 from spec.versions entirely:
#   status.storedVersions[0]: Invalid value: "v1beta1": missing from spec.versions; v1beta1 was previously a storage version,
#   and must remain in spec.versions until a storage migration ensures no data remains persisted in that version
kubectl patch customresourcedefinitions crontabs.example.com --subresource='status' --type='merge' -p '{"status":{"storedVersions":["v1"]}}'
# now the v1-only CRD is accepted: versions=v1 storedVersions=["v1"]
kubectl delete crd crontabs.example.com
```

## Lab 4 – Webhook conversion (docs CRD 04 + a real webhook)
```bash
./setup-webhook.sh           # CA + cert, webhook Deployment/Service, 04 applied with caBundle
kubectl apply -f crontabs-v1beta1.yaml        # local-crontab (localhost:1234), remote-crontab (example.com:2345) – the docs' objects
kubectl get ct -o custom-columns=NAME:.metadata.name,API:.apiVersion,HOST:.host,PORT:.port
#   local-crontab    example.com/v1   localhost     1234
#   remote-crontab   example.com/v1   example.com   2345
kubectl get crontabs.v1beta1.example.com -o custom-columns=NAME:.metadata.name,HOSTPORT:.hostPort
#   local-crontab    localhost:1234                 <- storage version: no webhook call
printf 'apiVersion: example.com/v1\nkind: CronTab\nmetadata: {name: new-v1}\nhost: db.internal\nport: "5432"\n' | kubectl apply -f -
$ET /registry/example.com/crontabs/default/new-v1 | grep -oE '"apiVersion":"[^"]*"|"hostPort":"[^"]*"' | head -2
#   "apiVersion":"example.com/v1beta1"   "hostPort":"db.internal:5432"        <- converted v1 -> v1beta1 before storing
kubectl logs deploy/example-conversion-webhook-server
#   review apiextensions.k8s.io/v1 uid=5d769365 -> v1 objects=['local-crontab@v1beta1'] Success
#   review apiextensions.k8s.io/v1 uid=d78f2403 -> v1 objects=['remote-crontab@v1beta1'] Success
#   review apiextensions.k8s.io/v1 uid=82b6056f -> v1beta1 objects=['new-v1@v1'] Success
#   review apiextensions.k8s.io/v1 uid=b1815a51 -> v1 objects=['new-v1@v1beta1'] Success
```
`ConversionReview` v1 was sent (first entry of `conversionReviewVersions: ["v1","v1beta1"]`).

### Failure, mutations, outage (not from the docs)
```bash
printf 'apiVersion: example.com/v1beta1\nkind: CronTab\nmetadata: {name: broken}\nhostPort: "no-port-here"\n' | kubectl apply -f -   # created (no conversion)
kubectl get ct broken
#   Error from server (InternalError): … StorageError: corrupt object … conversion webhook for example.com/v1beta1 … failed …
kubectl get ct
#   Error from server (StorageReadError): failed to read one or more crontabs.example.com from the storage: … corrupt object …   (Found #2)
kubectl delete ct broken                                   # same InternalError
kubectl delete crontabs.v1beta1.example.com broken         # deleted   <- via the storage version
kubectl logs deploy/example-conversion-webhook-server | grep Failed
#   review … -> v1 objects=['broken@v1beta1'] Failed: hostPort could not be parsed into a separate host and port     <- the docs' message
kubectl set env deploy/example-conversion-webhook-server ADD_LABEL=1      # allowed mutation (labels)
kubectl get ct local-crontab -o jsonpath='{.metadata.labels}'            # {"converted-by":"webhook"}  (also persisted for objects written via v1)
kubectl set env deploy/example-conversion-webhook-server ADD_LABEL=0 MUTATE_NAME=1   # forbidden mutation (name)
kubectl get ct local-crontab                                             # InternalError … corrupt object
kubectl set env deploy/example-conversion-webhook-server MUTATE_NAME=0
kubectl scale deploy/example-conversion-webhook-server --replicas=0     # outage (Found #3)
kubectl get ct                     # still lists all 5 (watch cache)
kubectl get ct fresh               # InternalError … corrupt object
# create via v1:      conversion webhook for example.com/v1, Kind=CronTab failed: Post "https://example-conversion-webhook-server.default.svc:443/crdconvert?timeout=30s": … connection refused
# create via v1beta1: created
kubectl scale deploy/example-conversion-webhook-server --replicas=1
```

## Lab 5 – Upgrade stored objects to v1 (docs option 1)
```bash
# 04 with storage moved to v1 (same caBundle):
CA=$(kubectl get crd crontabs.example.com -o jsonpath='{.spec.conversion.webhook.clientConfig.caBundle}')
sed "s|Ci0tLS0tQk...<base64-encoded PEM bundle>...tLS0K|$CA|" 04-my-versioned-crontab-with-conversion.yaml |
  python3 -c 'import yaml,sys,json; d=yaml.safe_load(sys.stdin); [v.update(storage=(v["name"]=="v1")) for v in d["spec"]["versions"]]; print(json.dumps(d))' | kubectl apply -f -
kubectl get crd crontabs.example.com -o jsonpath='{.status.storedVersions}'        # ["v1beta1","v1"]
$ET /registry/example.com/crontabs/default/local-crontab | grep -o '"apiVersion":"example.com[^"]*"' | head -1   # …/v1beta1  (not converted automatically)
kubectl apply -f 12-storageversionmigration.yaml
kubectl get storageversionmigration crontabs-migration -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}'   # Running=False Succeeded=True
$ET /registry/example.com/crontabs/default/local-crontab | grep -oE '"apiVersion":"example.com/[^"]*"|"host":"[^"]*"' | head -2
#   "apiVersion":"example.com/v1"   "host":"localhost"        <- rewritten through the webhook
kubectl get crd crontabs.example.com -o jsonpath='{.status.storedVersions}'        # ["v1"]   <- removed automatically
```
Option 2 (manual): read every object and write it back unchanged, then `kubectl patch … --subresource=status … storedVersions: ["v1"]` (used in Lab 3).
More on SVM: [storage-version-migration](../../../manage-kubernetes-objects/storage-version-migration/).

## Cleanup
```bash
./cleanup.sh
```
