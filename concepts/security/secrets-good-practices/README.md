# Good Practices for Kubernetes Secrets – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/secrets-good-practices/

> No YAML on the page. The central admin practice, **encryption at rest**, needs an API-server flag, so it runs on a separate minikube profile **`enc-lab`** ([start-enc-lab.sh](start-enc-lab.sh)) and the main cluster is never touched. [encryption-config.yaml](encryption-config.yaml) is the EncryptionConfiguration. [etcd-get.sh](etcd-get.sh) shows the raw bytes in etcd.

## Key ideas (read first)

| Audience | Practice | Shown in |
|---|---|---|
| Admin | **Encryption at rest** (`aescbc`, `aesgcm`, `secretbox`, or **KMS v2** with an external key service). Without it Secrets sit in etcd in plaintext. | Lab 1–3 here |
| Admin | **Least-privilege access**: `get` only on named Secrets, never `list`/`watch` broadly (list returns contents), remember Pod creation = Secret read | [../rbac-good-practices](../rbac-good-practices/) rows 1–2 |
| Admin | **etcd hygiene**: encrypt/wipe disks and backups, TLS between etcd peers, restrict etcd access | Lab 1 (what a backup thief reads) |
| Admin | **External secret stores** (Secrets Store CSI driver, External Secrets Operator), so data lives outside etcd | — |
| Admin | **Swap**: memory-backed Secret volumes need `noswap` (kernel ≥ 6.3) | [../linux-security](../linux-security/) |
| Developer | Mount Secrets only into the **container that needs them** | `../../configuration/secret` Lab 4 |
| Developer | **Protect data after reading**: don't log it, don't pass it in env to child processes, use files | — |
| Developer | **Don't share Secret manifests**: base64 is **encoding**, not encryption | `echo aHVudGVyMg== \| base64 -d` |

---

## Lab 1 – Turn on encryption at rest
```bash
cd concepts/security/secrets-good-practices
./start-enc-lab.sh
#   creates Secret "before-encryption" FIRST, then restarts kube-apiserver with
#   --encryption-provider-config=/var/lib/minikube/certs/encryption-config.yaml
kubectl --context enc-lab create secret generic after-encryption --from-literal=password=new-secret-value
./etcd-get.sh enc-lab default before-encryption
#   k8s.....v1..Secret........before-encryption....default ...         <- protobuf, readable: plaintext
./etcd-get.sh enc-lab default after-encryption
#   k8s:enc:aescbc:v1:key1:=.@..u...<.2.D......M......+..7vU...      <- provider:version:key name, then ciphertext
kubectl --context enc-lab get secret after-encryption -o jsonpath='{.data.password}' | base64 -d    # new-secret-value
```
Encryption is **transparent** to API clients. It protects etcd files, snapshots and backups, not API access (RBAC does that).

## Lab 2 – Existing Secrets are NOT re-encrypted by themselves
`before-encryption` stayed plaintext after the restart. Rewrite everything once:
```bash
kubectl --context enc-lab get secrets -A -o json | kubectl --context enc-lab replace -f -
./etcd-get.sh enc-lab default before-encryption     # k8s:enc:aescbc:v1:key1:...   <- now encrypted
```
Key rotation uses the same trick: add `key2` first (so it's used for writes), rewrite all Secrets, then remove `key1`.

## Lab 3 – Only what you list is encrypted
```bash
kubectl --context enc-lab create cm cfg --from-literal=k=not-a-secret
kubectl --context enc-lab exec -n kube-system etcd-enc-lab -- etcdctl --cacert /var/lib/minikube/certs/etcd/ca.crt \
  --cert /var/lib/minikube/certs/etcd/server.crt --key /var/lib/minikube/certs/etcd/server.key \
  get /registry/configmaps/default/cfg --print-value-only | grep -a -o not-a-secret       # not-a-secret
```
`resources: ["secrets"]` covers Secrets only. Add `configmaps` or custom resources if they hold sensitive data. And note that the aescbc key sits in a **file on the control-plane node**, so KMS v2 is the production choice.

```bash
minikube stop -p enc-lab ; kubectl config use-context minikube
```

---

## Useful commands
```bash
kubectl get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[]' | grep encryption
kubectl get secrets -A -o json | kubectl replace -f -          # force re-encryption with the current write key
kubectl get --raw /metrics | grep apiserver_storage_transformation_operations_total
```

## Cleanup
```bash
./cleanup.sh       # stops enc-lab (minikube delete -p enc-lab to remove it), switches back to minikube
```
