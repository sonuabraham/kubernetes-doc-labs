# Encrypting Confidential Data at Rest – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/

> The whole page runs on a throwaway profile **`encrypt-lab`**, and the raw bytes in etcd are checked at every step. Files:
> - Docs config files, **verbatim** with their `<BASE 64 ENCODED SECRET>` placeholder: [enc-config.yaml](enc-config.yaml), [enc-config-no-identity.yaml](enc-config-no-identity.yaml) and [enc-config-decrypt.yaml](enc-config-decrypt.yaml). Real keys are generated **on the node only** (`head -c 32 /dev/urandom | base64` → `/root/enc-key1`, `/root/enc-key2`) and filled in by [install-config.sh](install-config.sh), so no key ever enters this repo.
> - Helpers:
>   - [enable-encryption-config.sh](enable-encryption-config.sh) does the docs' manifest edit (flag + volumeMount + hostPath volume).
>   - [etcd-get.sh](etcd-get.sh) dumps a raw etcd value (`hexdump -C` style).
>   - [audit.sh](audit.sh) counts how every Secret is stored.
> - Rotation files: [enc-config-rotate-1/2/3.yaml](enc-config-rotate-1.yaml).
>
> The next page, [../decrypt-data](../decrypt-data/), continues on the same profile.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Default** | No `--encryption-provider-config` means objects are stored **in plaintext** in etcd (protobuf starting `k8s\0`). Anyone with an etcd backup can read Secrets. |
| **EncryptionConfiguration** | Per resource list, an ordered `providers` list. The **first** provider encrypts new writes. **All** providers are tried for reads, matched by the stored prefix `k8s:enc:<provider>:v1:<key>:`. `identity: {}` = plaintext. |
| **Providers** | `aescbc`, `aesgcm`, `secretbox` (local keys), `kms` v2 (keys held by an external KMS, recommended), `identity`. |
| **Existing data** | Is only re-encrypted when it's written again: `kubectl get secrets -A -o json \| kubectl replace -f -`. |
| **Drop identity** | Once everything is encrypted, remove `identity` so plaintext data can never be read, even by accident. |
| **Rotation** | Add the new key 2nd → reload everywhere → move it 1st → reload → rewrite all data → remove the old key. With `--encryption-provider-config-automatic-reload=true` the file is re-read about every minute, with no restarts. |
| **HA** | Every API server must have the **same** config. Plan each change so every server can always decrypt everything. |

---

## Step 0 – is encryption already on?
```bash
cd tasks/administer-cluster/encrypt-data
minikube start -p encrypt-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
K="kubectl --context encrypt-lab"
minikube ssh -p encrypt-lab -- 'sudo grep -c encryption-provider-config /etc/kubernetes/manifests/kube-apiserver.yaml'   # 0 -> no
$K create secret generic secret1 -n default --from-literal=mykey=mydata
./etcd-get.sh /registry/secrets/default/secret1 400
#   000000 6b 38 73 00 0a 0c 0a 02 76 31 12 06 53 65 63 72  >k8s.....v1..Secr<
#   ...
#   0000c0 22 3a 7b 7d 7d 42 00 12 0f 0a 05 6d 79 6b 65 79  >":{}}B.....mykey<
#   0000d0 12 06 6d 79 64 61 74 61 1a 06 4f 70 61 71 75 65  >..mydata..Opaque<      <- the value, readable in etcd
```

## Lab 1 – Key, config file, API server
```bash
./install-config.sh enc-config.yaml         # docs' file: secrets, configmaps, pandas.awesome.bears.example; aescbc key1 + identity
#   -rw------- 1 root root 523 ... /etc/kubernetes/enc/enc.yaml          <- root-only: it contains the key
./enable-encryption-config.sh
#   15:    - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml
#   83:    - name: enc      84: mountPath: /etc/kubernetes/enc      108: - name: enc   110: path: /etc/kubernetes/enc
#   API server ready
```
`pandas.awesome.bears.example` (a CRD that isn't installed) is accepted. The rule is simply waiting for that resource to exist.

## Lab 2 – Verify that newly written data is encrypted
```bash
$K create secret generic secret2 -n default --from-literal=mykey=mydata
./etcd-get.sh /registry/secrets/default/secret2 64
#   000000 6b 38 73 3a 65 6e 63 3a 61 65 73 63 62 63 3a 76  >k8s:enc:aescbc:v<
#   000010 31 3a 6b 65 79 31 3a f9 a7 06 6b cf 4a c3 9d 73  >1:key1:...k.J..s<      <- k8s:enc:aescbc:v1:key1: + ciphertext
$K get secret secret2 -n default -o jsonpath='{.data.mykey}'      # bXlkYXRh  (the API still returns it decrypted)
./etcd-get.sh /registry/secrets/default/secret1 16                # k8s.....v1..Secr   <- the OLD Secret is still plaintext
$K create configmap cm1 --from-literal=a=b; ./etcd-get.sh /registry/configmaps/default/cm1 32     # k8s:enc:aescbc:v1:key1: (configmaps listed too)
```

## Lab 3 – Ensure all relevant data are encrypted
```bash
$K get secrets --all-namespaces -o json | $K replace -f -
#   secret/secret1 replaced   secret/secret2 replaced   secret/bootstrap-token-yy11bw replaced
./audit.sh
#   3 k8s:enc:aescbc:v1:key1:
```

## Lab 4 – Prevent plain text retrieval (remove `identity`)
First see what `identity` still allows. This writes a **plaintext** Secret directly into etcd, as an old backup restore would:
```bash
minikube ssh -p encrypt-lab -- "sudo bash -c 'crictl exec \$(crictl ps -q --name etcd) etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/minikube/certs/etcd/ca.crt --cert=/var/lib/minikube/certs/etcd/server.crt --key=/var/lib/minikube/certs/etcd/server.key \
  put /registry/secrets/default/legacy-plain \"{\\\"kind\\\":\\\"Secret\\\",\\\"apiVersion\\\":\\\"v1\\\",\\\"metadata\\\":{\\\"name\\\":\\\"legacy-plain\\\",\\\"namespace\\\":\\\"default\\\",\\\"uid\\\":\\\"11111111-2222-3333-4444-555555555555\\\",\\\"creationTimestamp\\\":\\\"2026-01-01T00:00:00Z\\\"},\\\"data\\\":{\\\"pw\\\":\\\"b2xkLXNlY3JldA==\\\"},\\\"type\\\":\\\"Opaque\\\"}\"'"
./audit.sh                   # 3 k8s:enc:aescbc:v1:key1:   1 { (plain JSON)
$K get secret legacy-plain -o jsonpath='{.data.pw}' | base64 -d          # old-secret   <- read through the identity fallback
```
Now remove `identity` ([enc-config-no-identity.yaml](enc-config-no-identity.yaml)) and restart the API server:
```bash
./install-config.sh enc-config-no-identity.yaml
minikube ssh -p encrypt-lab -- 'sudo bash -c "mkdir -p /tmp/off; mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/off/; sleep 15; mv /tmp/off/kube-apiserver.yaml /etc/kubernetes/manifests/"'
$K get secret legacy-plain
#   Error from server (InternalError): ... StorageError: corrupt object, Code: 7, Key: /secrets/default/legacy-plain ...
#   data from the storage is not transformable revision=0: no matching prefix found
$K get secrets
#   Error from server (StorageReadError): failed to read one or more secrets from the storage: ...   <- ONE bad object breaks LIST!
```
That is the page's warning: check that **everything** is encrypted before dropping `identity`. To remove such an unreadable object, use the API's unsafe-delete option (feature `AllowUnsafeMalformedObjectDeletion`, beta in 1.37). kubectl has no flag for it, so send the `DeleteOptions` directly:
```bash
echo '{"kind":"DeleteOptions","apiVersion":"v1","ignoreStoreReadErrorWithClusterBreakingPotential":true}' > /tmp/unsafe-delete.json
$K delete --raw /api/v1/namespaces/default/secrets/legacy-plain -f /tmp/unsafe-delete.json
#   {"kind":"Status",...,"status":"Success","details":{"name":"legacy-plain","kind":"Secret"},"code":200}
$K get secrets                # works again
```

## Lab 5 – Rotate the key without restarts (automatic reload)
```bash
./enable-encryption-config.sh --auto-reload          # adds --encryption-provider-config-automatic-reload=true (one restart)
reloads(){ $K get --raw /metrics | grep -E '^apiserver_encryption_config_controller_automatic_reloads_total'; }
./install-config.sh enc-config-rotate-1.yaml         # key1, key2   (key2 can decrypt, not used yet)
reloads                                              # ...{...,status="success"} 1     (~43 s later, no restart)
./install-config.sh enc-config-rotate-2.yaml         # key2, key1   (new writes use key2)
$K create secret generic secret3 --from-literal=k=v; ./audit.sh
#   3 k8s:enc:aescbc:v1:key1:
#   1 k8s:enc:aescbc:v1:key2:
$K get secrets -A -o json | $K replace -f -; ./audit.sh
#   4 k8s:enc:aescbc:v1:key2:
./install-config.sh enc-config-rotate-3.yaml         # key2 only - key1 retired
$K get secret secret1 -o jsonpath='{.data.mykey}' | base64 -d          # mydata
```
`apiserver_encryption_config_controller_automatic_reload_last_timestamp_seconds` shows when a new config took effect. Continue with [../decrypt-data](../decrypt-data/) to turn encryption off again.

---

## Useful commands
```bash
head -c 32 /dev/urandom | base64
kubectl get secrets -A -o json | kubectl replace -f -
etcdctl get /registry/secrets/<ns>/<name> --print-value-only | hexdump -C | head
kubectl get --raw /metrics | grep apiserver_encryption_config_controller
```

## Cleanup
```bash
minikube delete -p encrypt-lab       # (after the decrypt-data lab)
```
