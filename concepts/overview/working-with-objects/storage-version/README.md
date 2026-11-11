# Storage Versions – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/working-with-objects/storage-version/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Storage version** | The API version an object is **serialized as in etcd**, for example the v1 encoding of a ConfigMap. It is separate from the version a client used to read or write the object. |
| **Automatic conversion** | Clients can mix versions (HPA `autoscaling/v1` and `v2`). The API server converts every call, so clients never see what's actually stored. |
| **One at a time** | Each resource has **one active** storage version, and every write stores at that version. Each object is stored at exactly one version, but different objects of a resource can sit at **different** versions after the storage version changes. |
| **Reads vs writes** | Reads convert the stored data without changing it, so an old storage version can stay indefinitely. **Writes** re-encode the object at the current storage version. |
| **Built-in types** | The stored form is a "hub" that's independent of the API versions. |
| **CRDs** | Exactly **one** version has `storage: true`, and its **schema** is used for encoding. With `conversion: None`, fields that aren't in the storage schema are pruned. `status.storedVersions` lists every version that might still be in etcd. |
| **Why admins care** | (1) You can't remove an old CRD version while objects may still be stored in it. (2) **Encryption at rest**: after a key rotation, old keys stay needed until every object has been rewritten. |
| **Migration** | Rewrite every object so it's stored at the current version: a `StorageVersionMigration` (served as `storagemigration.k8s.io/v1` on this cluster), or a no-op update of every object. |

## The demo app
[crontab-crd.yaml](crontab-crd.yaml) is the docs' CRD **verbatim**: `crontabs.example.com`, v1beta1 is the storage version, v1 adds a `time` field, and `conversion: None`.
[etcdctl.sh](etcdctl.sh) reads etcd directly (see `../../components`). [stored-as.sh](stored-as.sh) prints the apiVersion each crontab has **inside etcd**.

---

## Step 1
```bash
cd concepts/overview/working-with-objects/storage-version
kubectl apply -f 00-namespace.yaml
```

## Lab 1 – Built-in types: write v1, stored as v2
```bash
kubectl apply -f 01-hpa-via-v1.yaml                                  # written through autoscaling/v1
./etcdctl.sh get /registry/horizontalpodautoscalers/storage-version-demo/web --print-value-only | strings | grep -m1 autoscaling
#   autoscaling/v2                                                   <- what is really in etcd
kubectl get --raw /apis/autoscaling/v1/namespaces/storage-version-demo/horizontalpodautoscalers/web | jq -c '{apiVersion, cpu: .spec.targetCPUUtilizationPercentage}'
kubectl get --raw /apis/autoscaling/v2/namespaces/storage-version-demo/horizontalpodautoscalers/web | jq -c '{apiVersion, cpu: .spec.metrics[0].resource.target.averageUtilization}'
#   both 70 - converted on every read
```

## Lab 2 – CRD storage version (the docs example)
```bash
kubectl apply -f crontab-crd.yaml
kubectl wait --for=condition=Established crd/crontabs.example.com
kubectl apply -f 02-crontab-v1beta1.yaml -f 03-crontab-v1-with-time.yaml
kubectl get crontab.v1.example.com new-style -n storage-version-demo -o json | jq -c '{apiVersion, host, port, time}'
#   {"apiVersion":"example.com/v1","host":"web.example.com","port":"80","time":null}    <- "time" is GONE
./stored-as.sh
#   /registry/example.com/crontabs/storage-version-demo/new-style  example.com/v1beta1
#   /registry/example.com/crontabs/storage-version-demo/old-style  example.com/v1beta1
kubectl get crd crontabs.example.com -o jsonpath='{.status.storedVersions}{"\n"}'     # ["v1beta1"]
```
This is the docs' point: "the `v1` API object would never be able to store the `time` field", because the object is encoded with the v1beta1 schema.

## Lab 3 – Change the storage version
Two storage versions at once is invalid:
```bash
kubectl apply -f 05-two-storage-versions.yaml 2>&1 | grep -o 'must have exactly one version marked as storage version'
```
Move storage to v1. [04-crontab-crd-storage-v1.yaml](04-crontab-crd-storage-v1.yaml) is the docs CRD with the two `storage:` values swapped.
```bash
kubectl apply -f 04-crontab-crd-storage-v1.yaml
kubectl apply -f 03-crontab-v1-with-time.yaml                          # a WRITE to new-style only
kubectl get ct new-style -n storage-version-demo -o json | jq -c '{apiVersion, time}'
#   {"apiVersion":"example.com/v1","time":"*/5 * * * *"}               <- time is kept now
./stored-as.sh
#   new-style  example.com/v1          <- rewritten by the update
#   old-style  example.com/v1beta1     <- untouched: reads don't migrate
kubectl get crd crontabs.example.com -o jsonpath='{.status.storedVersions}{"\n"}'     # ["v1beta1","v1"]
```
While `storedVersions` contains `v1beta1` you must not remove v1beta1 from the CRD. etcd may still hold objects you then couldn't read.

## Lab 4 – Migrate everything
```bash
kubectl apply -f 06-storage-version-migration.yaml
kubectl get storageversionmigration crontabs-to-v1 -o json | jq -c '.status.conditions[] | {type, status, reason}'
#   {"type":"Running","status":"False","reason":"MigrationCompleted"}
#   {"type":"Succeeded","status":"True","reason":"StorageVersionMigrationSucceeded"}
./stored-as.sh                                                       # both example.com/v1
kubectl get crd crontabs.example.com -o jsonpath='{.status.storedVersions}{"\n"}'     # ["v1"]
```
On v1.37 the migration also trimmed `storedVersions` to `["v1"]`, so v1beta1 could now be removed from the CRD (`served: false`, then delete the version).
Manual alternative without the API: `kubectl get crontabs -A -o json | kubectl replace -f -`. Every no-op update re-encodes an object.

## Lab 5 – Storage versions and encryption at rest
```bash
kubectl create secret generic db-pass -n storage-version-demo --from-literal=password=SuperSecret123
./etcdctl.sh get /registry/secrets/storage-version-demo/db-pass --print-value-only | strings | grep SuperSecret
#   SuperSecret123      <- minikube has no encryption at rest: Secrets sit in etcd in plaintext
```
With an `EncryptionConfiguration`, the stored bytes start with `k8s:enc:<provider>:v1:<key>:`. That prefix is part of the "storage version": the API server needs that key to read the object. After you add a new key, objects stay encrypted with the old one until they're **written again**, so you run the same migration as in Lab 4, but for `secrets`. Setting up encryption is covered under `../../../security/secrets-good-practices`.

---

## Useful commands
```bash
kubectl get crd <name> -o jsonpath='{.status.storedVersions}'
kubectl get crd <name> -o jsonpath='{range .spec.versions[*]}{.name} served={.served} storage={.storage}{"\n"}{end}'
kubectl get storageversionmigrations
./etcdctl.sh get /registry/<group>/<resource>/<ns>/<name> --print-value-only
```

## Cleanup
```bash
./cleanup.sh
```
