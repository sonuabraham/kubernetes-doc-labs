# Cloud Native Security and Kubernetes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/cloud-native-security/

> A conceptual page (no YAML), built on the CNCF cloud native security white paper. This lab maps each **lifecycle phase** to something you can check on a real cluster. [audit.sh](audit.sh) is a read-only report for your minikube.

## Key ideas (read first)

| Phase | Goal | Kubernetes levers (where in this repo) |
|---|---|---|
| **Develop** | Secure dev environments, secure-by-design apps, think about end users | Code review, tests, [application security checklist](../application-security-checklist/) |
| **Distribute** | Trustworthy **supply chain** for images and cluster components | Scanning, signing (Sigstore), SBOMs, **pin by digest**, private registries + pull secrets (`../../containers/images`) |
| **Deploy** | Control **what** can be deployed, **who** can deploy it, **where** | Admission control ([Pod Security Admission](../pod-security-admission/), ValidatingAdmissionPolicy), namespaces, quotas, RBAC |
| **Runtime: access** | Protect the API | TLS everywhere, authentication, [RBAC](../rbac-good-practices/), [controlling access](../controlling-access/), audit logs |
| **Runtime: compute** | Isolate workloads | [Pod Security Standards](../pod-security-standards/), seccomp/AppArmor/SELinux ([Linux kernel constraints](../linux-kernel-security-constraints/)), RuntimeClass sandboxes, dedicated nodes |
| **Runtime: storage** | Protect data | Encryption at rest (Secrets, volumes), backups, [Secrets good practices](../secrets-good-practices/) |
| **Networking** | Limit and encrypt traffic | NetworkPolicy (`../../services-networking/network-policies`), service-mesh mTLS / CNI encryption |
| **Observability** | Detect and respond | Audit logs, runtime detection (e.g. Falco), metrics with secured pipelines |

---

## Lab 1 – Audit your cluster against the phases
```bash
cd concepts/security/cloud-native-security
./audit.sh
```
Measured on this minikube:
```
== DISTRIBUTE   pinned by digest: 10   by tag: 8   latest/untagged: 0
== DEPLOY       enable-admission-plugins: NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,
                  DefaultTolerationSeconds,NodeRestriction,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota
                namespaces with Pod Security Admission labels: (none)              <- nothing restricts Pod specs
== ACCESS       authorization-mode: Node,RBAC
                unauthenticated GET /api/v1/namespaces -> 403   (anonymous reaches authz, which denies)
                unauthenticated GET /version -> 200             (public by design: system:public-info-viewer)
                plain HTTP to the API port -> 400               (TLS only)
                audit logging: OFF
== KUBELET      anonymous auth: false   authz mode: Webhook   readOnlyPort: 0      <- good
== COMPUTE      pods: 14  privileged containers: 4  hostNetwork pods: 7
                pods without runAsNonRoot: 13  containers without limits: 17
== STORAGE      encryption-provider-config: NOT set -> Secrets in etcd as plaintext
== NETWORKING   NetworkPolicies defined: 0   CNI: kindnet
```
A dev cluster is wide open on Deploy, Storage and Observability. Each gap has its own lab in this section. (The privileged and hostNetwork Pods are system components: kube-proxy, kindnet, the CSI plugin, etcd…)

## Lab 2 – Distribute: pin images by digest
```bash
kubectl create namespace cns-demo
kubectl run tagged -n cns-demo --image=busybox:1.36 -- sleep 3600
D=$(kubectl get pod tagged -n cns-demo -o jsonpath='{.status.containerStatuses[0].imageID}') ; echo $D
#   docker.io/library/busybox@sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662
kubectl run pinned -n cns-demo --image=$D -- sleep 3600
kubectl get pods -n cns-demo -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
```
`busybox:1.36` can be re-pushed to point at different bytes. `busybox@sha256:…` can't. Signature verification (an admission webhook checking cosign signatures) builds on digests.

## Lab 3 – Follow the phases through this section
| Do this lab | To close this gap from the audit |
|---|---|
| [pod-security-admission](../pod-security-admission/) | no PSA labels |
| [linux-kernel-security-constraints](../linux-kernel-security-constraints/), [linux-security](../linux-security/) | root, privileged |
| [rbac-good-practices](../rbac-good-practices/), [controlling-access](../controlling-access/) | access |
| [secrets-good-practices](../secrets-good-practices/) | plaintext Secrets |
| `../../services-networking/network-policies` | 0 NetworkPolicies |

---

## Useful commands
```bash
kubectl get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[]'
kubectl get --raw /api/v1/nodes/<n>/proxy/configz | jq .kubeletconfig.authentication
kubectl get pods -A -o jsonpath='{range .items[*]}{.status.containerStatuses[*].imageID}{"\n"}{end}' | sort -u
```

## Cleanup
```bash
./cleanup.sh
```
