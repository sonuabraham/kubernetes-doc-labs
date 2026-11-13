# Decrypt Confidential Data that is Already Encrypted at Rest – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/decrypt-data/

> This continues on the **`encrypt-lab`** profile from [../encrypt-data](../encrypt-data/): 4 Secrets encrypted with `aescbc` key **key2**, automatic reload on. The helpers live there: `install-config.sh` (fills keys in on the node), `audit.sh` and `etcd-get.sh`. Files:
> - Docs YAML, **verbatim**: [01-existing-config-docs.yaml](01-existing-config-docs.yaml) ("if your existing file reads") and [02-identity-first-docs.yaml](02-identity-first-docs.yaml) ("change it to").
> - [03-identity-first-lab.yaml](03-identity-first-lab.yaml) is the same change made with this cluster's real key.

## Key ideas (read first)

| Step | Why |
|---|---|
| Find `--encryption-provider-config` in the kube-apiserver manifest and the hostPath mount | That's where the config file lives on each control-plane node. |
| Put `identity: {}` **first**, keep the old provider **after** it | New writes are plaintext, and the old key is still needed to **read** the encrypted data. |
| Restart or reload every API server (same config everywhere) | |
| `kubectl get secrets -A -o json \| kubectl replace -f -` | Rewrites every object, and so stores it plaintext. |
| Only then remove `--encryption-provider-config` (and `...-automatic-reload`) and restart | If anything is still encrypted, it becomes unreadable. |

---

## Step 0 – where is the config, what does it say?
```bash
cd tasks/administer-cluster/decrypt-data
K="kubectl --context encrypt-lab"
minikube ssh -p encrypt-lab -- 'sudo grep -E "encryption-provider|/etc/kubernetes/enc" /etc/kubernetes/manifests/kube-apiserver.yaml'
#   - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml
#   - --encryption-provider-config-automatic-reload=true
#   mountPath: /etc/kubernetes/enc      path: /etc/kubernetes/enc        <- hostPath
../encrypt-data/audit.sh            # 4 k8s:enc:aescbc:v1:key2:     (first provider is aescbc -> encryption is on)
```

## Lab 1 – The docs' example key is invalid on purpose
```bash
echo 2KfZgdiq2K0g2YrYpyDYs9mF2LPZhQ== | base64 -d | wc -c        # 22 - AES needs 16, 24 or 32 bytes
../encrypt-data/install-config.sh 01-existing-config-docs.yaml
# ~1 min later (automatic reload):
$K get --raw /metrics | grep -E '^apiserver_encryption_config_controller_automatic_reloads_total' | grep -oE 'status="[a-z]+"\} [0-9]+'
#   status="failure"} 9
#   status="success"} 3
minikube ssh -p encrypt-lab -- 'sudo bash -c "crictl logs \$(crictl ps -q --name kube-apiserver) 2>&1 | grep encryption | tail -1"'
#   "error processing encryption config file /etc/kubernetes/enc/enc.yaml: error while parsing file:
#    resources[0].providers[0].aescbc.keys[0].secret: Invalid value: \"REDACTED\": secret is not ..."
$K get secret secret1 -o jsonpath='{.data.mykey}'     # bXlkYXRh  <- the bad file was rejected; the last good config stays active
```
With a restart instead of a reload, the API server would refuse to start with this file.

## Lab 2 – identity first, then force decryption
```bash
../encrypt-data/install-config.sh 03-identity-first-lab.yaml      # identity: {}, then aescbc key2
# wait for the next successful reload (status="success" counter +1), then:
../encrypt-data/audit.sh                       # 4 k8s:enc:aescbc:v1:key2:   <- nothing changes until data is rewritten
$K get secrets --all-namespaces -o json | $K replace -f -
../encrypt-data/audit.sh                       # 4 k8s.. (plain protobuf)
```

## Lab 3 – Remove the encryption settings from the API server
```bash
minikube ssh -p encrypt-lab -- 'sudo cp /root/kube-apiserver.orig.yaml /etc/kubernetes/manifests/kube-apiserver.yaml'   # drops both flags + the mount
until $K get --raw /readyz >/dev/null 2>&1; do sleep 3; done
$K get secrets -A
#   default       secret1   Opaque   1 ...   secret2 ...   secret3 ...   kube-system   bootstrap-token-...
$K get secret secret1 -o jsonpath='{.data.mykey}' | base64 -d       # mydata
$K get --raw /metrics | grep -c apiserver_encryption_config_controller     # 0 - encryption machinery gone
```

---

## Useful commands
```bash
grep -E "encryption-provider" /etc/kubernetes/manifests/kube-apiserver.yaml
kubectl get secrets -A -o json | kubectl replace -f -
kubectl get --raw /metrics | grep apiserver_encryption_config_controller_automatic_reloads_total
```

## Cleanup
```bash
minikube delete -p encrypt-lab
```
