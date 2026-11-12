# Application Security Checklist – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/application-security-checklist/

> The checklist is for **application developers** (the [Security Checklist](../security-checklist/) is for cluster admins). [01-hardened-app.yaml](01-hardened-app.yaml) is one web app that ticks every base item (each line annotated `[x]`), [02-naive-app.yaml](02-naive-app.yaml) is the usual first draft, and [lint.sh](lint.sh) grades a Deployment against the list.

## Key ideas (read first)

| Area | Checklist items |
|---|---|
| **Design** | Follow app security principles; pick a QoS class (requests/limits) |
| **ServiceAccount** | Not `default`; `automountServiceAccountToken: false` unless the app calls the API |
| **Pod securityContext** | `runAsNonRoot: true`, a less-privileged `runAsUser`/`runAsGroup`, `fsGroup` for volumes, a namespace enforcing a Pod Security Standard |
| **Container securityContext** | `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `privileged: false`, drop `ALL` capabilities (add back only what's needed) |
| **RBAC** | No create/patch/update/delete unless needed; nothing that can create roles; review `system:unauthenticated` bindings |
| **Images** | Scan before deploying; verify signatures |
| **Network** | NetworkPolicies: only the traffic the app needs |
| **Advanced** | seccomp, AppArmor, SELinux; RuntimeClass sandboxes |

---

## Lab 1 – Lint both versions
```bash
cd concepts/security/application-security-checklist
./lint.sh 01-hardened-app.yaml       # 11/11 [x]
./lint.sh 02-naive-app.yaml
#   [ ] dedicated ServiceAccount          [ ] automountServiceAccountToken: false
#   [ ] runAsNonRoot: true                [ ] non-root runAsUser          [ ] seccompProfile set
#   [ ] allowPrivilegeEscalation: false   [ ] readOnlyRootFilesystem: true
#   [x] not privileged                    [ ] capabilities drop ALL
#   [ ] requests+limits (QoS)             [ ] image pinned (no :latest/untagged)
```

## Lab 2 – The hardened app actually works
```bash
kubectl apply -f 01-hardened-app.yaml ; kubectl rollout status deploy/web -n appsec-demo
kubectl get pod -n appsec-demo -l app=web -o jsonpath='{.items[0].status.qosClass}'          # Guaranteed
P=$(kubectl get pod -n appsec-demo -l app=web -o name | head -1)
kubectl exec -n appsec-demo $P -- id                                   # uid=101(nginx) gid=101(nginx)
kubectl exec -n appsec-demo $P -- touch /etc/x                         # Read-only file system
kubectl exec -n appsec-demo $P -- ls /var/run/secrets/kubernetes.io    # No such file or directory (no SA token)
```
The tricks that make it work: an image built for non-root (`nginx-unprivileged` listens on **8080**, so no `NET_BIND_SERVICE` is needed), and **emptyDirs** for the paths nginx writes (`/tmp`, `/var/cache/nginx`) under a read-only root filesystem.

## Lab 3 – The namespace refuses the naive version
```bash
kubectl apply -n appsec-demo -f 02-naive-app.yaml
#   Warning: would violate PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false ...
#   deployment.apps/naive-web created
kubectl get events -n appsec-demo --field-selector reason=FailedCreate -o custom-columns=M:.message | tail -1
#   Error creating: pods "naive-web-…" is forbidden: violates PodSecurity "restricted:v1.37": ...
```

## Lab 4 – Network policy: only the intended client
```bash
kubectl create ns appsec-client
kubectl run c -n appsec-client --image=busybox:1.36 -- sleep 3600 ; kubectl run c -n default --image=busybox:1.36 -- sleep 3600
kubectl exec c -n appsec-client -- wget -q -T 3 -O /dev/null http://web.appsec-demo && echo OK        # OK
kubectl exec c -n default       -- wget -q -T 3 -O /dev/null http://web.appsec-demo || echo BLOCKED   # BLOCKED
```

---

## Useful commands
```bash
./lint.sh <manifest.yaml>
kubectl apply --dry-run=server -n appsec-demo -f <manifest>     # let PSA grade it too
```

## Cleanup
```bash
./cleanup.sh
```
