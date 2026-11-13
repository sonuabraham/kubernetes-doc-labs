# Securing a Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/securing-a-cluster/

> The page is a checklist, so this lab is a **read-only audit**: [security-audit.sh](security-audit.sh) goes through the page section by section against the default **minikube** cluster. It reads configuration and makes **unauthenticated** requests (to the API server, the kubelet and etcd) to show what each control actually does. Nothing is changed. [kubernetes-blacklist.conf](kubernetes-blacklist.conf) is the page's module blocklist, **verbatim**. Each finding links to the lab that shows how to fix it.

## Key ideas (read first)

| Page section | What to look for |
|---|---|
| TLS for all API traffic | No plaintext port. Clients must trust the cluster CA. |
| API authentication | Who is anonymous, which authenticators are on (certs, tokens, OIDC). |
| API authorization | `--authorization-mode=Node,RBAC`. Minimal bindings, and few subjects with `cluster-admin`. |
| Kubelet | `authentication.anonymous.enabled=false`, `authorization.mode=Webhook`, read-only port 10255 off. |
| Runtime capabilities | ResourceQuotas/LimitRanges, Pod Security Admission, seccomp, unneeded kernel modules blocked, NetworkPolicies, cloud metadata blocked, node isolation. |
| Protect components | etcd only reachable with client certs, audit logging, alpha/beta features off, short-lived credentials, encryption at rest, vetted third-party integrations. |

---

## Lab – Run the audit
```bash
cd tasks/administer-cluster/securing-a-cluster
./security-audit.sh minikube
```
Results on this cluster (✔ = good, ✘ = gap, with the lab that fixes it):

```
== TLS for all API traffic
  plain http to :8443 -> 400                      ✔ only TLS is spoken
  https without trusting the CA -> 000 (exit 60)  ✔ clients need the cluster CA
== API authentication
  anonymous-auth flag: (not set -> anonymous requests ENABLED)
  anonymous GET /version   -> 200                 (allowed on purpose: health/discovery)
  anonymous GET /api/v1/namespaces -> namespaces is forbidden: User "system:anonymous" cannot list resource ...   ✔ RBAC stops it
== API authorization
  --authorization-mode=Node,RBAC                  ✔
  anonymous GET /api/v1/secrets -> 403            ✔
  can kube-system:default SA do everything? yes   ✘ minikube binds kube-system/default to cluster-admin ("minikube-rbac")
  can default SA list secrets?       no           ✔
  subjects bound to cluster-admin: cluster-admin[Group:/system:masters ] kubeadm:cluster-admins[...] minikube-rbac[ServiceAccount:kube-system/default ]
== Kubelet access
  authentication: anonymous: enabled: false  webhook: ...   authorization: mode: Webhook      ✔
  readOnlyPort: (unset -> 0, disabled)            ✔
  anonymous GET https://<node>:10250/pods -> 401  ✔
  read-only port http://<node>:10255/pods -> 000 (exit 7)    ✔ connection refused
== Limiting resource usage
  every namespace: quotas=0 limitranges=0         ✘ -> ../manage-resources, ../quota-api-object, ../limit-storage-consumption
== Container privileges
  no namespace has pod-security.kubernetes.io/enforce        ✘ -> Pod Security Admission (tasks/configure-pod-container)
  privileged containers running: csi-* hostpath kube-proxy   (system components that need it)
  kubelet seccompDefault: (unset -> false)        ✘ containers run Unconfined unless they ask
== Unwanted kernel modules
  dccp loaded=no blocked=no ; sctp loaded=no blocked=no       ✘ not blocked -> kubernetes-blacklist.conf
== Network access
  NetworkPolicies: 0 in 0 namespaces              ✘ -> ../declare-network-policy
== etcd access
  --client-cert-auth=true --listen-client-urls=https://127.0.0.1:2379,https://<node>:2379
  https://<node>:2379/version without client cert -> 000 (exit 55)   ✔ TLS handshake refused without a client cert
== Audit logging
  audit-policy-file: (not set -> NO audit log)    ✘ -> tasks/debug "Auditing"
== Alpha/beta features
  apiserver: no --feature-gates  no --runtime-config        ✔ defaults only (-> ../configure-feature-gates)
== Secrets encrypted at rest
  encryption-provider-config: (not set -> Secrets stored in PLAINTEXT in etcd)   ✘ -> ../encrypt-data
== Credential lifetimes
  apiserver.crt notAfter=Nov 6 2029 ; apiserver-kubelet-client.crt notAfter=Nov 7 2027   -> ../kubeadm/kubeadm-certs
  legacy SA token Secrets: 0                      ✔ (short-lived projected tokens instead)
```

## Blocking unneeded kernel modules
The page's file (`/etc/modprobe.d/kubernetes-blacklist.conf` on every node):
```
blacklist dccp
blacklist sctp
```
That keeps an unprivileged Pod from auto-loading these modules by opening a socket of that protocol. On a real node you'd copy it to `/etc/modprobe.d/` (root, and **not** inside minikube's shared kernel, where it would affect the host).

---

## Useful commands
```bash
kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa>
kubectl get clusterrolebindings -o wide | grep cluster-admin
kubectl get ns -L pod-security.kubernetes.io/enforce
curl -sk https://<apiserver>/api/v1/secrets          # what does anonymous get?
```

## Cleanup
Nothing to clean up: the audit is read-only.
