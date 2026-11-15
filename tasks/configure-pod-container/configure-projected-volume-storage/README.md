# Configure a Pod to Use a Projected Volume for Storage – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/configure-projected-volume-storage/

> Runs on the default **minikube** cluster, in the `default` namespace as in the docs.
> File: [projected.yaml](projected.yaml) (docs, **verbatim**).
> Not from the docs: [projected-all-sources.yaml](projected-all-sources.yaml), which uses all four source types together.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`projected` volume** | One directory filled from several sources: `secret`, `configMap`, `downwardAPI`, `serviceAccountToken`. Plus `clusterTrustBundle` and `podCertificate` in newer releases; see [concepts/storage/projected-volumes](../../../concepts/storage/projected-volumes/). |
| **`serviceAccountToken`** | Not a volume type of its own, only a projected source: a short-lived token with your `audience` and `expirationSeconds`, rotated by the kubelet. |
| **`items` / `path` / `mode`** | Pick keys, rename them (sub-directories allowed), and set per-file modes. `defaultMode` covers the rest. |
| **Atomic updates** | Files are symlinks into a timestamped `..data` directory. On a change the kubelet writes a new directory and swaps `..data`, so readers never see half a file. **Not** for `subPath` mounts. |
| **Conflicts** | Two sources that write the same path are rejected by the API server. |

```
/projected-volume/
├── ..2026_11_15_02_53_33.2845946659/   (real files)
├── ..data -> ..2026_11_15_…             (swapped atomically on update)
├── username.txt -> ..data/username.txt  ← secret "user"
└── password.txt -> ..data/password.txt  ← secret "pass"
```

---

## Step 0 – The Secrets (docs)
```bash
cd tasks/configure-pod-container/configure-projected-volume-storage
echo -n "admin" > ./username.txt
echo -n "1f2d1e2e67df" > ./password.txt
kubectl create secret generic user --from-file=./username.txt
kubectl create secret generic pass --from-file=./password.txt
rm username.txt password.txt          # not in the docs: don't leave the plaintext lying around
```

## Lab 1 – Two Secrets in one directory (docs)
```bash
kubectl apply -f projected.yaml
kubectl get --watch pod test-projected-volume          # Ctrl-C once Running
kubectl exec test-projected-volume -- ls -la /projected-volume/
#   drwxr-xr-x  ..2026_11_15_02_53_33.2845946659
#   lrwxrwxrwx  ..data -> ..2026_11_15_02_53_33.2845946659
#   lrwxrwxrwx  password.txt -> ..data/password.txt
#   lrwxrwxrwx  username.txt -> ..data/username.txt
kubectl exec test-projected-volume -- sh -c 'cat /projected-volume/username.txt; echo; cat /projected-volume/password.txt'
#   admin
#   1f2d1e2e67df
```

## Lab 2 – All four sources, renamed paths and modes (not from the docs)
```bash
kubectl apply -f projected-all-sources.yaml
kubectl exec projected-all-sources -- sh -c 'cd /projected-volume; ls; ls -lL creds; cat labels'
#   creds  labels  mode  token
#   -r--------  password       <- items[].mode 0400
#   -r--r-----  username       <- defaultMode 0440
#   app="demo"                 <- downwardAPI metadata.labels
kubectl exec projected-all-sources -- cat /projected-volume/token | cut -d. -f2 \
  | tr '_-' '/+' | { read p; while [ $(( ${#p} % 4 )) -ne 0 ]; do p="$p="; done; echo "$p" | base64 -d; } \
  | jq -c '{aud, sub, exp_minus_iat:(.exp-.iat), pod:."kubernetes.io".pod.name}'
#   {"aud":["vault"],"sub":"system:serviceaccount:default:default","exp_minus_iat":3600,"pod":"projected-all-sources"}
```
The token is bound to this Pod: it stops working when the Pod is deleted, and it only works for audience `vault`.

## Lab 3 – Live update (not from the docs)
```bash
kubectl create secret generic pass --from-literal=password.txt=NEWPASS --dry-run=client -o yaml | kubectl apply -f -
for i in $(seq 1 30); do v=$(kubectl exec test-projected-volume -- cat /projected-volume/password.txt)
  [ "$v" = NEWPASS ] && { echo "updated after ~$((i*3))s"; break; }; sleep 3; done
#   updated after ~57s       <- kubelet sync period (~1 min) + cache TTL; no restart needed
```

## Lab 4 – Two sources, same path (not from the docs)
```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: projected-collision}
spec:
  containers: [{name: shell, image: busybox:1.28, args: ["sleep","86400"], volumeMounts: [{name: v, mountPath: /pv}]}]
  volumes:
  - name: v
    projected:
      sources:
      - secret: {name: user, items: [{key: username.txt, path: same}]}
      - secret: {name: pass, items: [{key: password.txt, path: same}]}
EOF
#   The Pod "projected-collision" is invalid:
#   * spec.volumes[0].projected: Invalid value: "pass": conflicting duplicate paths
```

## Useful commands
```bash
kubectl exec <pod> -- ls -la <mountPath>           # see the ..data symlink layout
kubectl get pod <pod> -o jsonpath='{.spec.volumes[?(@.projected)]}' | jq .
```

## Cleanup
```bash
./cleanup.sh     # both Pods, Secrets user/pass, ConfigMap app-config
```
