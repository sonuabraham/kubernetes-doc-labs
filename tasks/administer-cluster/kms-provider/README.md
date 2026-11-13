# Using a KMS provider for data encryption – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/kms-provider/

> This is a working **KMS v2** setup on a throwaway profile **`kms-lab`**. The KMS plugin is written here in Go with the library the page recommends (`k8s.io/kms/pkg/service`): [lab-kms-plugin/main.go](lab-kms-plugin/main.go). Its "remote KMS" is a local KEK file, generated on the node and never in this repo. Files:
> - Docs configs, **verbatim**: [enc-kms-v1-docs.yaml](enc-kms-v1-docs.yaml), [enc-kms-v2-docs.yaml](enc-kms-v2-docs.yaml), [enc-switch-to-kms-docs.yaml](enc-switch-to-kms-docs.yaml).
> - [enc-kms-v2-lab.yaml](enc-kms-v2-lab.yaml): the v2 config with this lab's single plugin and real socket path.
> - Helpers: [setup-node.sh](setup-node.sh) (installs and runs the plugin, wires the API server, rotates the KEK), [kek-audit.sh](kek-audit.sh) (which KEK protects each Secret), and `../encrypt-data/etcd-get.sh` / `audit.sh` (raw etcd bytes).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Envelope encryption** | Objects are encrypted locally with a **DEK**. Only the DEK goes to the KMS, to be wrapped with a **KEK** that never leaves the KMS. etcd stores `k8s:enc:kms:v2:<name>:` + ciphertext + the wrapped DEK + `key_id`. |
| **KMS v2** | GA since 1.29. The API server generates DEKs from a seed and caches the unwrapped DEKs (no `cachesize`). The plugin is a gRPC server on a Unix socket with `Status`, `Encrypt` and `Decrypt`. |
| **KMS v1** | Deprecated, and **off** unless `--feature-gates=KMSv1=true`. |
| **`Status`** | Polled about every minute. Returns `version: v2`, `healthz: ok`, and the current **`key_id`**, which is authoritative: when it changes, the KEK has been rotated. |
| **Rotation** | Rotate the KEK in the KMS. Within about a minute new writes use it, with no restart. A no-op rewrite (`kubectl get … | kubectl replace -f -`) moves old objects to the new KEK. Rotate at least every 90 days. Never reuse a `key_id`. |
| **Health** | `/readyz/kms-providers` (`/healthz/kms-provider-N` with individual v1 checks). |

---

## Step 0 – build the plugin, start a cluster
```bash
cd tasks/administer-cluster/kms-provider
docker run --rm -e GOTOOLCHAIN=auto -v $PWD/lab-kms-plugin:/src -w /src golang:1.25 sh -c \
  'go mod tidy && CGO_ENABLED=0 go build -o lab-kms-plugin . && chown -R 1000:1000 /src'       # ~15 MB, gitignored
minikube start -p kms-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
K="kubectl --context kms-lab"
$K create secret generic before-kms --from-literal=k=old          # written before encryption is on
```

## Lab 1 – Deploy the plugin and configure the API server
```bash
./setup-node.sh plugin
#   Running as unit: lab-kms-plugin.service   active   srwxr-xr-x ... /var/run/kmsplugin/socket.sock
./setup-node.sh apiserver enc-kms-v2-lab.yaml
#   (adds --encryption-provider-config + --encryption-provider-config-automatic-reload, and mounts /etc/kubernetes/enc
#    AND the socket dir /var/run/kmsplugin into the API server Pod - a socket in the host's /tmp, as in the
#    docs' example paths, would be invisible to the containerized API server)
#   API server ready
$K get --raw /readyz/kms-providers          # ok
```
The docs' v2 file lists **two** plugins (`/tmp/socketfile-foo.sock`, `/tmp/socketfile-bar.sock`). Every listed plugin must be running and healthy, which is why the lab config has just the one that exists.

**What the first attempt taught (developing a plugin):** the plugin initially returned the annotation key `lab-kms.example.com/kek`. The provider stayed unhealthy:
```
$K get --raw /readyz/kms-providers
#   kms-provider-0: kmsv2 Provider labKmsPlugin is not healthy, error: failed to rotate DEK ..., errGen=failed to validate annotations:
#   annotations: Invalid value: "lab-kms.example.com/kek": a lowercase RFC 1123 subdomain must consist of ... (e.g. 'example.com', ...)
```
Annotation keys must be DNS subdomains **without a path**. The page's example key `kms.example.io/remote-kms-auditid` would be rejected the same way. The plugin now uses `kek.lab-kms.example.com`.

## Lab 2 – Verify that the data is encrypted
```bash
$K create secret generic secret1 -n default --from-literal=mykey=mydata
P=kms-lab ../encrypt-data/etcd-get.sh /registry/secrets/default/secret1 48
#   000000 6b 38 73 3a 65 6e 63 3a 6b 6d 73 3a 76 32 3a 6c  >k8s:enc:kms:v2:l<
#   000010 61 62 4b 6d 73 50 6c 75 67 69 6e 3a 0a a0 02 c0  >abKmsPlugin:....<
$K describe secret secret1 -n default        # Data: mykey: 6 bytes   (decrypted transparently)
P=kms-lab ../encrypt-data/etcd-get.sh /registry/secrets/default/before-kms 16
#   000000 6b 38 73 00 0a 0c 0a 02 76 31 12 06 53 65 63 72  >k8s.....v1..Secr<   <- the old one is still plaintext
```

## Lab 3 – Ensure all secrets are encrypted
```bash
$K get secrets --all-namespaces -o json | $K replace -f -
P=kms-lab ../encrypt-data/audit.sh                 # 3 k8s:enc:kms:v2:labKmsPl...
```
Then remove `identity: {}` from the config (see [../encrypt-data](../encrypt-data/) Lab 4 for why to check first).

## Lab 4 – Rotate the KEK (no API server restart)
```bash
./kek-audit.sh
#   /registry/secrets/default/before-kms   kek-1      /registry/secrets/default/secret1   kek-1   ...
./setup-node.sh rotate                              # appends kek-2 to the KMS's key file: kek-2 is now current
#   kek-1 kek-2 (last = current)
$K get --raw /metrics | grep ^apiserver_envelope_encryption_key_id_hash_status_last_timestamp | grep -oE 'key_id_hash="sha256:[0-9a-f]{12}'
#   key_id_hash="sha256:3dd688dad3aa      <- seen via Status ~21 s later (hashes, not raw key ids, are exposed)
#   key_id_hash="sha256:6ad4ff2bfd37
$K create secret generic after-rotation --from-literal=k=v
./kek-audit.sh
#   after-rotation kek-2     before-kms kek-1     secret1 kek-1     <- new writes use the new KEK, old data still readable
$K get secrets --all-namespaces -o json | $K replace -f -              # "no-op" writes: stale key_id -> re-encrypted
./kek-audit.sh                                                          # everything kek-2
$K get secret before-kms -o jsonpath='{.data.k}' | base64 -d           # old
```

## Lab 5 – KMS v1 is off by default
Swap the docs' v1 config in (automatic reload is on):
```bash
minikube -p kms-lab cp enc-kms-v1-docs.yaml /etc/kubernetes/enc/enc.yaml
# ~1 min later, in the kube-apiserver log:
#   err="error processing encryption config file /etc/kubernetes/enc/enc.yaml: error while building transformers:
#   KMSv1 is deprecated and will only receive security updates going forward. Use KMSv2 instead.  Set --feature-gates=KMSv1=true to use the deprecated KMS ..."
$K get secret secret1 -o jsonpath='{.data.mykey}' | base64 -d          # mydata - the last good (v2) config stays active
```
Switching from a local provider (`aescbc`) to KMS is [enc-switch-to-kms-docs.yaml](enc-switch-to-kms-docs.yaml): KMS first, `aescbc` after it so old data can still be read, then `replace` everything. It's the same flow as Labs 1–3.

---

## Useful commands
```bash
kubectl get --raw /readyz/kms-providers
kubectl get --raw /metrics | grep apiserver_envelope_encryption
journalctl -u lab-kms-plugin -f                     # plugin log: Encrypt/Decrypt calls with key_id
```

## Cleanup
```bash
minikube delete -p kms-lab
```
