# Projected Volumes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/projected-volumes/

> The docs' 5 example manifests are here **verbatim** (`projected-*.yaml`, from the website's `examples/pods/storage/`). [00-prereqs.yaml](00-prereqs.yaml) creates the Secrets and ConfigMap they name. [make-trust-bundles.sh](make-trust-bundles.sh) creates the ClusterTrustBundles they select. [toy-signer.sh](toy-signer.sh) is a minimal signer for the `coolcert.example.com/foo` pod certificates.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **projected** | One volume, one directory, **several sources** merged: `secret`, `configMap`, `downwardAPI`, `serviceAccountToken`, `clusterTrustBundle`, `podCertificate`. |
| **Same rules as standalone** | Secret/ConfigMap must be in the Pod's namespace. `items` pick keys and paths. `defaultMode` / per-item `mode`. Updates are atomic via the `..data` symlink swap. |
| **subPath** | A projected source mounted with `subPath` does **not** receive updates. |
| **serviceAccountToken** | A bound, short-lived JWT: `audience` (default: the API server), `expirationSeconds` (min 600, default 1h). The kubelet refreshes it at 80% of its lifetime or after 24h. |
| **clusterTrustBundle** (GA in v1.37) | Writes the CA certificates of a `ClusterTrustBundle` (cluster-scoped) to a file, selected by `name`, or by `signerName` + `labelSelector`. `optional: true` → an empty file instead of a stuck Pod. |
| **podCertificate** (GA in v1.37) | The kubelet makes a key (`keyType`), files a `PodCertificateRequest` for `signerName`, waits for a **signer** to issue it, writes key+chain (`credentialBundlePath`, or separate `keyPath`/`certificateChainPath`), and refreshes it at `beginRefreshAt`. |
| **SecurityContext (Linux)** | If the Pod sets `runAsUser` (and all containers agree), the **token** file is owned by that UID with mode `0600`. Other files keep their modes. |
| **Windows** | No ownership mapping: files are owned by Administrators/SYSTEM and readable by Users, as the docs' `Get-Acl` output shows. |

---

## Step 1
```bash
cd concepts/storage/projected-volumes
kubectl apply -f 00-prereqs.yaml
kubectl apply -n proj-demo  -f projected-secret-downwardapi-configmap.yaml -f projected-service-account-token.yaml
kubectl apply -n proj-demo2 -f projected-secrets-nondefault-permission-mode.yaml     # same Pod name "volume-test"
```

## Lab 1 – Secret + downwardAPI + configMap in one directory
```bash
kubectl exec volume-test -n proj-demo -- ls -la /projected-volume
#   ..2026_11_11_22_23_24.1880289359/
#   ..data -> ..2026_11_11_…          <- atomic update mechanism
#   cpu_limit -> ..data/cpu_limit
#   labels -> ..data/labels
#   my-group -> ..data/my-group       <- secret AND configMap both write into my-group/
kubectl exec volume-test -n proj-demo -- sh -c 'cd /projected-volume; for f in my-group/my-username my-group/my-config labels cpu_limit; do echo "$f: $(cat $f)"; done'
#   my-group/my-username: admin
#   my-group/my-config: log_level=debug
#   labels:                       <- the Pod has no labels yet
#   cpu_limit: 8                  <- no limit set, so the node's allocatable CPU
kubectl label pod volume-test -n proj-demo tier=backend
kubectl exec volume-test -n proj-demo -- cat /projected-volume/labels     # tier="backend"   (a few seconds later)
```

## Lab 2 – Per-item mode
```bash
kubectl exec volume-test -n proj-demo2 -- ls -lL /projected-volume/my-group/
#   -rwxrwxrwx  my-password     <- mode: 0777 on that item
#   -rw-r--r--  my-username     <- defaultMode 0644
```

## Lab 3 – serviceAccountToken
```bash
kubectl exec sa-token-test -n proj-demo -- cat /service-account/token | cut -d. -f2 | base64 -d 2>/dev/null | jq '{aud, ttl:(.exp-.iat), sub, pod:.["kubernetes.io"].pod.name}'
#   { "aud": ["api"], "ttl": 3600, "sub": "system:serviceaccount:proj-demo:default", "pod": "sa-token-test" }
```
The token is **bound** to the Pod: delete the Pod and the API server rejects it. (Add `=` padding if `base64 -d` complains.)

## Lab 4 – SecurityContext interaction
```bash
kubectl apply -f 01-runasuser-token.yaml
for p in token-runas token-root; do kubectl exec $p -n proj-demo -- ls -lnL /service-account/; done
#   token-runas:  -rw-r--r-- 0    config  |  -rw------- 1000 token     <- token owned by runAsUser, 0600
#   token-root:   -rw-r--r-- 0    config  |  -rw-r--r-- 0    token
```

## Lab 5 – clusterTrustBundle
```bash
kubectl apply -n proj-demo -f projected-clustertrustbundle.yaml
kubectl get events -n proj-demo --field-selector involvedObject.name=sa-ctb-name-test,type=Warning -o custom-columns=M:.message
#   MountVolume.SetUp failed for volume "token-vol" : ... clustertrustbundle.certificates.k8s.io "example" not found
#   (the by-name source isn't optional, so the Pod waits in ContainerCreating)
./make-trust-bundles.sh
#   clustertrustbundle.certificates.k8s.io/example created
#   clustertrustbundle.certificates.k8s.io/example.com:mysigner:live-roots created   <- signer bundles must be named <signer with / → :>:<anything>
kubectl exec sa-ctb-name-test -n proj-demo -- ls /root-certificates           # example-roots.pem  mysigner-roots.pem
kubectl exec sa-ctb-name-test -n proj-demo -- cat /root-certificates/mysigner-roots.pem | openssl x509 -noout -subject
#   subject=CN=mysigner-root      <- picked by signerName + label version=live
```

## Lab 6 – podCertificate with a toy signer
```bash
kubectl apply -f projected-podcertificate.yaml          # namespace default (set in the manifest)
kubectl get podcertificaterequests
#   NAME        PODNAME              SIGNERNAME                 STATE     UNVERIFIEDUSERANNOTATIONS
#   req-pmqvz   podcertificate-pod   coolcert.example.com/foo   Pending   example.com/annotation1=value1,...
#   The Pod stays ContainerCreating - nobody signs for coolcert.example.com/foo yet
./toy-signer.sh                                         # terminal 2; keep running
#   09:24:59 issued default/req-pmqvz for pod podcertificate-pod (valid until 2026-11-12T22:24:59Z)
kubectl wait --for=condition=Ready pod/podcertificate-pod
kubectl exec podcertificate-pod -- grep -- -----BEGIN /var/run/my-x509-credentials/credentialbundle.pem
#   -----BEGIN PRIVATE KEY-----        <- generated by the kubelet, never left the node
#   -----BEGIN CERTIFICATE-----
kubectl exec podcertificate-pod -- cat /var/run/my-x509-credentials/credentialbundle.pem | openssl x509 -noout -subject -issuer -text | grep -E 'subject=|issuer=|Public Key Algorithm'
#   subject=CN=podcertificate-pod.default
#   issuer=CN=coolcert toy CA
#   Public Key Algorithm: ED25519      <- keyType: ED25519
```
The signer only sees the PodCertificateRequest: a stub CSR (`stubPKCS10Request`) with the public key, plus pod, node and service-account identity, plus `unverifiedUserAnnotations`. It writes `certificateChain`, `notBefore`/`notAfter`/`beginRefreshAt` and an `Issued` condition into status. The API server requires a lifetime of at least 1h.

---

## Useful commands
```bash
kubectl explain pod.spec.volumes.projected.sources
kubectl get clustertrustbundles ; kubectl get podcertificaterequests -A
kubectl exec <pod> -- ls -la <mountPath>       # the ..data symlink layout
```

## Cleanup
```bash
./cleanup.sh       # namespaces, podcertificate-pod (default), trust bundles, toy CA. Stop toy-signer.sh with Ctrl-C.
```
