# Migrate Kubernetes Objects Using Storage Version Migration – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/storage-version-migration/

> Needs encryption at rest with automatic config reload, so it runs on a throwaway profile **`svm-lab`** using the helper scripts of
> [administer-cluster/encrypt-data](../../administer-cluster/encrypt-data/) with `P=svm-lab`. Stop the default `minikube` first (inotify limit).
> Docs files, **verbatim**: [enc-config-key1.yaml](enc-config-key1.yaml), [enc-config-key2.yaml](enc-config-key2.yaml),
> [migrate-secret.yaml](migrate-secret.yaml), [test-crd.yaml](test-crd.yaml), [test-crd-v2.yaml](test-crd-v2.yaml), [cr1.yaml](cr1.yaml),
> [cr2.yaml](cr2.yaml), [migrate-crd.yaml](migrate-crd.yaml). The docs' example keys are used as-is (they're public).
> Not from the docs: [enc-config-key2-identity.yaml](enc-config-key2-identity.yaml), [test-crd-fixed.yaml](test-crd-fixed.yaml),
> [test-crd-v2-fixed.yaml](test-crd-v2-fixed.yaml).
>
> **Docs problems found:**
> 1. The encryption configs have **no `identity: {}` fallback**. Any Secret written before encryption was enabled (on minikube:
>    kubeadm's `bootstrap-token-…`) becomes unreadable. The API server's `/readyz` fails (`informer-sync`), the node never gets
>    a CNI (kindnet waits for the API), and the Secret migration ends **Failed**.
> 2. `test-crd.yaml` has `caBundle: <CABundle info>`, so it's rejected (`illegal base64 data`). There is no conversion webhook anyway.
> 3. `test-crd-v2.yaml` has `name:` **outside** `metadata` (`resource name may not be empty`).
> 4. The etcd paths `/kubernetes.io/example.com/testcrds/…` and the final `kubectl get crd testcrds.example.com` don't match the
>    CRD the page creates (`selfierequests`, and minikube's prefix is `/registry`).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Why migrate** | etcd keeps each object as it was **last written**: old encryption key, old CRD storage version. Nothing rewrites them on its own. |
| **StorageVersionMigration** (`storagemigration.k8s.io/v1`, GA, on by default) | Asks kube-controller-manager to rewrite every object of one resource (a no-op update), so each is stored again with the *current* encryption key / storage version. |
| **Status** | `Running` → `Succeeded` (or `Failed`). For CRDs, `status.storedVersions` is trimmed to the current version afterwards. |
| **Requirement** | integer resourceVersions: all built-ins and CRDs, but not aggregated APIs |

---

## Step 0 – Profile with encryption (key1)
```bash
cd tasks/manage-kubernetes-objects/storage-version-migration
minikube stop
minikube start -p svm-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0
export P=svm-lab; ED=../../administer-cluster/encrypt-data; K="kubectl --context svm-lab"
$ED/install-config.sh enc-config-key1.yaml          # -> /etc/kubernetes/enc/enc.yaml on the node
$ED/enable-encryption-config.sh --auto-reload       # --encryption-provider-config(+ -automatic-reload=true)
$K create secret generic my-secret --from-literal=key1=supersecret                     # docs
$ED/etcd-get.sh /registry/secrets/default/my-secret 32
#   000000  6b 38 73 3a 65 6e 63 3a 61 65 73 63 62 63 3a 76  >k8s:enc:aescbc:v<
#   000010  31 3a 6b 65 79 31 3a …                              >1:key1:…<
```

## Lab 1 – Rotate the key; old data stays old
```bash
$ED/install-config.sh enc-config-key2.yaml          # key2 first (writes), key1 second (reads)
$K get --raw /metrics | grep '^apiserver_encryption_config_controller_automatic_reloads_total'
#   …{…,status="success"} 1            <- picked up without an API server restart
$ED/etcd-get.sh /registry/secrets/default/my-secret 32                  # still …key1…
$K create secret generic new-secret --from-literal=a=b
$ED/etcd-get.sh /registry/secrets/default/new-secret 32                 # …key2…
$ED/audit.sh /registry/secrets
#   1 k8s.. (plain protobuf)                 <- the bootstrap token from before encryption!
#   1 k8s:enc:aescbc:v1:key1:
#   1 k8s:enc:aescbc:v1:key2:
```

## Lab 2 – The docs' migration, and why it failed here
```bash
$K apply -f migrate-secret.yaml
$K wait --for=condition=Succeeded storageversionmigration.storagemigration.k8s.io/secrets-migration
#   error: timed out …        (status: Running/MigrationRunning … later Failed/StorageVersionMigrationFailed)
$K get secrets -A
#   Error from server (StorageReadError): … StorageError: corrupt object … Key: /registry/secrets/kube-system/bootstrap-token-563ffw …
$K get --raw '/readyz?verbose'        # … [-]informer-sync failed …
$K get nodes                          # NotReady - kindnet never wrote its CNI config; coredns Pending
```
Neither aescbc key can read that unencrypted Secret, and there's no `identity` provider to fall back to. That one object blocks the
API server's Secret informer, everything waiting on it, and the migration (which must read every Secret).

## Lab 3 – Fix: identity as the last (read-only) provider, migrate again
```bash
$ED/install-config.sh enc-config-key2-identity.yaml       # = docs' key2 config + "- identity: {}" at the end
$K get secrets -A                                          # works again (4 Secrets); the node turns Ready
$K delete storageversionmigration secrets-migration; $K apply -f migrate-secret.yaml
$K wait --for=condition=Succeeded storageversionmigration.storagemigration.k8s.io/secrets-migration
$K get storageversionmigration secrets-migration -o json | jq -c '[.status.conditions[]|{type,status,reason}]'
#   [{"type":"Running","status":"False","reason":"MigrationCompleted"},{"type":"Succeeded","status":"True","reason":"StorageVersionMigrationSucceeded"}]
$ED/audit.sh /registry/secrets
#   4 k8s:enc:aescbc:v1:key2:          <- everything rewritten with key2, including the old plain bootstrap token
```
Only now is it safe to remove `key1` (and `identity`) from the config.

## Lab 4 – CRD storage version v1 → v2
```bash
$K apply -f test-crd.yaml
#   … cannot be handled as a CustomResourceDefinition: illegal base64 data at input byte 0          <- <CABundle info>
$K apply -f test-crd-v2.yaml
#   … resource name may not be empty                                                               <- name: outside metadata
eg(){ minikube -p svm-lab ssh -- "sudo bash -c 'crictl exec \$(crictl ps -q --name etcd) etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/minikube/certs/etcd/ca.crt --cert=/var/lib/minikube/certs/etcd/server.crt --key=/var/lib/minikube/certs/etcd/server.key \
  get $1 --print-value-only'" | tr -d '\r' | jq -c '{apiVersion}'; }
$K apply -f test-crd-fixed.yaml                       # conversion: None
$K get crd selfierequests.example.com -o jsonpath='storage={.spec.versions[?(@.storage==true)].name} storedVersions={.status.storedVersions}'
#   storage=v1 storedVersions=["v1"]
$K apply -f cr1.yaml; eg /registry/example.com/selfierequests/default/cr1          # {"apiVersion":"example.com/v1"}
$K apply -f test-crd-v2-fixed.yaml                    # v2 = storage, v1 still served
#   storage=v2 storedVersions=["v1","v2"]
$K apply -f cr2.yaml; eg /registry/example.com/selfierequests/default/cr2          # {"apiVersion":"example.com/v2"}
eg /registry/example.com/selfierequests/default/cr1                                 # still {"apiVersion":"example.com/v1"}
$K apply -f migrate-crd.yaml
$K wait --for=condition=Succeeded storageversionmigration/crdsvm
eg /registry/example.com/selfierequests/default/cr1                                 # {"apiVersion":"example.com/v2"}   <- rewritten
$K get crd selfierequests.example.com -o jsonpath='{.status.storedVersions}'        # ["v2"]   <- v1 can now be removed from the CRD
```
Custom resources are stored as JSON, so the stored `apiVersion` is readable directly. A real v1 → v2 change of fields (`hostPort` →
`host` + `port`) needs a conversion webhook: see [custom-resource-definition-versioning](../../extend-kubernetes/custom-resources/custom-resource-definition-versioning/).

## Step 5 – Back to the default cluster
```bash
./cleanup.sh       # minikube delete -p svm-lab
minikube start
```

## Useful commands
```bash
kubectl get storageversionmigrations
kubectl get crd <name> -o jsonpath='{.status.storedVersions}'
kubectl get --raw '/readyz?verbose' | grep -v '\[+\]'
```

## Cleanup
```bash
./cleanup.sh
```
