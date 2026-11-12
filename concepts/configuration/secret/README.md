# Secrets – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/configuration/secret/

> The docs' 9 example manifests are here **verbatim** (from the website's `examples/secret/`), plus [immutable-secret-excerpt.yaml](immutable-secret-excerpt.yaml) (literal `...`). Everything runs in namespace `secret-demo`, except the bootstrap token, which is pinned to `kube-system`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Secret** | Small sensitive data (passwords, tokens, keys), kept out of Pod specs and images. Same mechanics as ConfigMaps: env, files, `imagePullSecrets`, API. Max **1 MiB**. |
| **Not encrypted by default** | `data` is just **base64**. Stored **in plaintext in etcd** unless you configure encryption at rest. Anyone who can create a Pod in a namespace can read that namespace's Secrets. |
| **data / stringData** | base64 values / plain strings (merged into `data`, `stringData` wins). |
| **Types** | `Opaque`; `kubernetes.io/service-account-token` (legacy long-lived token); `kubernetes.io/dockercfg` / `dockerconfigjson`; `basic-auth` (`username`+`password`); `ssh-auth` (`ssh-privatekey`); `tls` (`tls.crt`+`tls.key`); `bootstrap.kubernetes.io/token`. Typed Secrets are **validated**. |
| **Files** | Mounted on **tmpfs** (never on node disk), atomic updates like ConfigMaps (not for subPath). `defaultMode` / per-item `mode`. Dotfiles are hidden from `ls -l`. |
| **Env vars** | `secretKeyRef` / `envFrom`. No updates, and they easily leak into logs and crash dumps. |
| **One container only** | Mount the Secret only in the container that needs it. Others in the Pod can't see it. |
| **imagePullSecrets** | On the Pod, or attached to its **ServiceAccount** so every Pod gets them automatically. |
| **optional / immutable** | Same as ConfigMaps. Immutable also protects the API server and kubelets from watch load. |
| **Good practice** | Encryption at rest, least-privilege RBAC (watch out for `list` and Pod creation), short-lived projected tokens instead of SA token Secrets, external secret stores (CSI driver). |

---

## Step 1 – Create the docs Secrets
```bash
cd concepts/configuration/secret
kubectl create namespace secret-demo
for f in basicauth-secret dockercfg-secret ssh-auth-secret tls-auth-secret dotfile-secret optional-secret; do kubectl apply -n secret-demo -f $f.yaml; done
#   tls-auth-secret: Secret in version "v1" cannot be handled as a Secret: illegal base64 data at input byte 7
#   ("REPLACE_WITH_BASE64_CERT" isn't base64: it's a placeholder, as its comment says)
kubectl get secret -n secret-demo
#   dotfile-secret      Opaque                     1
#   secret-basic-auth   kubernetes.io/basic-auth   2
#   secret-dockercfg    kubernetes.io/dockercfg    1
#   secret-ssh-auth     kubernetes.io/ssh-auth     1
```

## Lab 1 – Typed Secrets are validated
```bash
S=$(mktemp -d); openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=demo.example.com -keyout $S/tls.key -out $S/tls.crt
kubectl create secret tls secret-tls -n secret-demo --cert=$S/tls.crt --key=$S/tls.key            # the real way to make the docs' TLS Secret
kubectl create secret generic bad-basic -n secret-demo --type=kubernetes.io/basic-auth --from-literal=user=x
#   data[username]: Required value, data[password]: Required value
kubectl create secret generic bad-ssh -n secret-demo --type=kubernetes.io/ssh-auth --from-literal=key=x
#   data[ssh-privatekey]: Required value
kubectl create secret generic bad-dockercfg -n secret-demo --type=kubernetes.io/dockercfg --from-literal=.dockercfg=notjson
#   data[.dockercfg]: Invalid value: "<secret contents redacted>": invalid character 'o' ...    <- must be JSON; note the redaction
```

## Lab 2 – ServiceAccount token Secret (legacy)
```bash
kubectl apply -n secret-demo -f serviceaccount-token-secret.yaml ; kubectl get secret secret-sa-sample -n secret-demo
#   NotFound   <- the token controller DELETES it: ServiceAccount "sa-name" doesn't exist
kubectl create sa sa-name -n secret-demo ; kubectl apply -n secret-demo -f serviceaccount-token-secret.yaml
kubectl get secret secret-sa-sample -n secret-demo -o json | jq -c '.data|keys'      # ["ca.crt","extra","namespace","token"]
kubectl get secret secret-sa-sample -n secret-demo -o jsonpath='{.data.token}' | base64 -d | cut -d. -f2 | base64 -d 2>/dev/null | jq -c '{sub, exp}'
#   {"sub":"system:serviceaccount:secret-demo:sa-name","exp":null}    <- NEVER expires: prefer projected tokens (../../storage/projected-volumes)
```

## Lab 3 – Bootstrap token (docs, kube-system)
```bash
kubectl apply -f bootstrap-token-secret-literal.yaml        # (the -base64 variant is the same object, encoded)
sleep 20 ; kubectl get secret bootstrap-token-5emitj -n kube-system
#   NotFound   <- its expiration is 2020-09-13: the tokencleaner controller (enabled on minikube) removed it
```

## Lab 4 – Dotfiles, env, one container only
```bash
sed -e 's#registry.k8s.io/busybox#busybox:1.36#' -e 's/secret-dotfiles-pod/secret-dotfiles-pod-136/' dotfile-secret.yaml | kubectl apply -n secret-demo -f -
kubectl logs secret-dotfiles-pod-136 -n secret-demo          # total 0   <- `ls -l` hides .secret-file (`ls -la` shows it)
```
The docs Pod as written (`registry.k8s.io/busybox`) is `ErrImagePull`: Docker schema-1 media type, which containerd 2 won't pull.
```bash
kubectl apply -n secret-demo -f 01-secret-usage.yaml
kubectl exec secret-consumer -c frontend -n secret-demo -- sh -c 'echo $DB_USER; ls -lL /etc/creds/db; mount | grep creds'
#   app
#   -r--------  password                         <- defaultMode 0400, items path db/password
#   tmpfs on /etc/creds type tmpfs (ro,...)      <- RAM, never written to the node's disk
kubectl exec secret-consumer -c sidecar -n secret-demo -- ls /etc/creds
#   ls: /etc/creds: No such file or directory    <- same Pod, no access
```

## Lab 5 – Optional Secret (docs `mypod`)
```bash
kubectl get pod mypod -n secret-demo          # Running - mysecret doesn't exist, the volume is optional (empty)
```

## Lab 6 – imagePullSecrets
```bash
kubectl create secret docker-registry regcred -n secret-demo --docker-server=registry.example.com --docker-username=bob --docker-password=pw
kubectl get secret regcred -n secret-demo -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
#   {"auths":{"registry.example.com":{"username":"bob","password":"pw","auth":"Ym9iOnB3"}}}
kubectl apply -n secret-demo -f 02-imagepullsecret-pod.yaml        # manual: spec.imagePullSecrets
kubectl patch sa default -n secret-demo -p '{"imagePullSecrets":[{"name":"regcred"}]}'
kubectl run auto-pull -n secret-demo --image=busybox:1.36 -- sleep 3600
kubectl get pod auto-pull -n secret-demo -o jsonpath='{.spec.imagePullSecrets}'     # [{"name":"regcred"}]   <- added at admission
```

## Lab 7 – Immutable and size
```bash
kubectl create secret generic frozen -n secret-demo --from-literal=k=v --dry-run=client -o json | jq '.immutable=true' | kubectl apply -f -
kubectl patch secret frozen -n secret-demo -p '{"stringData":{"k":"new"}}'
#   data: Forbidden: field is immutable when `immutable` is set
head -c 1100000 /dev/urandom > big.bin ; kubectl create secret generic too-big -n secret-demo --from-file=big.bin ; rm big.bin
#   data: Too long: may not be more than 1048576 bytes
```

## Lab 8 – Why least privilege is hard
```bash
kubectl apply -n secret-demo -f 03-least-privilege.yaml     # SA pod-creator: may create/read Pods, NOT Secrets
AS=--as=system:serviceaccount:secret-demo:pod-creator
kubectl auth can-i get secrets -n secret-demo $AS                 # no
kubectl get secret db-creds -n secret-demo $AS                    # Forbidden
kubectl run thief -n secret-demo $AS --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"volumes":[{"name":"s","secret":{"secretName":"db-creds"}}],"containers":[{"name":"thief","image":"busybox:1.36","command":["cat","/s/password"],"volumeMounts":[{"name":"s","mountPath":"/s"}]}]}}'
kubectl logs thief -n secret-demo $AS                             # s3cr3t-pw
```
Pod creation **is** Secret read access for that namespace. Separate namespaces by trust, or restrict which Secrets Pods may mount with admission policy.

## Lab 9 – Plaintext in etcd
```bash
kubectl exec -n kube-system etcd-minikube -- etcdctl --cacert /var/lib/minikube/certs/etcd/ca.crt \
  --cert /var/lib/minikube/certs/etcd/server.crt --key /var/lib/minikube/certs/etcd/server.key \
  get /registry/secrets/secret-demo/db-creds | grep -a -o 's3cr3t-pw'
#   s3cr3t-pw          <- readable by anyone with etcd (or etcd backup) access
```
With encryption at rest the value starts with `k8s:enc:aescbc:v1:…` / `k8s:enc:kms:v2:…` instead. See `../../security/secrets-good-practices`.

---

## Useful commands
```bash
kubectl create secret generic <n> --from-literal=k=v --from-file=<f>
kubectl create secret tls <n> --cert=<crt> --key=<key>
kubectl create secret docker-registry <n> --docker-server=... --docker-username=... --docker-password=...
kubectl get secret <n> -o jsonpath='{.data.<key>}' | base64 -d
kubectl auth can-i get secrets -n <ns> --as=<user>
```

## Cleanup
```bash
./cleanup.sh
```
