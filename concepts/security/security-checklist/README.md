# Security Checklist – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/security-checklist/

> The checklist is a list of `- [ ]` items, not YAML. [checklist.sh](checklist.sh) automates every item that can be read from the API (read-only) and marks the rest **MANUAL**. Each FAIL links to the lab that shows the fix.

## Key ideas (read first)

| Section | Items (abridged) | Where in this repo |
|---|---|---|
| **AuthN & AuthZ** | no `system:masters` after bootstrap; controller-manager `--use-service-account-credentials`; protected root CA; certs ≤ 3 years; periodic access review; RBAC good practices | [controlling-access](../controlling-access/), [rbac-good-practices](../rbac-good-practices/), [hardening-guide/authentication-mechanisms](../hardening-guide/authentication-mechanisms/) |
| **Network** | CNI enforces NetworkPolicy; ingress+egress policies; default deny per namespace; mesh mTLS; API/kubelet/etcd not public; metadata API filtered; restricted LoadBalancer/ExternalIPs | [multi-tenancy](../multi-tenancy/), `../../services-networking/network-policies` |
| **Pod security** | least workload RBAC; PSS enforced; memory limits (limit ≤ request); CPU limits for sensitive workloads; seccomp; AppArmor/SELinux | [pod-security-admission](../pod-security-admission/), [linux-kernel-security-constraints](../linux-kernel-security-constraints/) |
| **Logs & auditing** | audit logs protected | [cloud-native-security](../cloud-native-security/) |
| **Pod placement** | placement by sensitivity tier; sensitive apps isolated (nodes, sandboxes) | `../../scheduling-eviction` |
| **Secrets** | no confidential data in ConfigMaps; encryption at rest; external stores; no unneeded SA tokens; bound tokens | [secrets-good-practices](../secrets-good-practices/), [service-accounts](../service-accounts/) |
| **Images** | minimal images; non-root user; **digests**; scanning | [cloud-native-security](../cloud-native-security/) Lab 2 |
| **Admission** | appropriate plugins; PSA or policy engine; securely configured webhooks | [pod-security-policy](../pod-security-policy/) (VAP migration) |

---

## Lab – Run the checklist against minikube
```bash
cd concepts/security/security-checklist
./checklist.sh
```
Measured on a fresh minikube (lab namespaces cleaned up):
```
## Authentication & Authorization
FAIL    system:masters not used for users (your kubeconfig is in system:masters: true)
PASS    kube-controller-manager --use-service-account-credentials
MANUAL  root CA protected (offline/managed); leaf certs <= 3y; periodic access reviews
## Network security
INFO    NetworkPolicies: 0 across 4 namespaces (CNI must enforce them - kindnet does)
PASS    no LoadBalancer/externalIPs Services (restricted use)
MANUAL  API/kubelet/etcd not exposed to the Internet; cloud metadata API filtered; service mesh mTLS
## Pod security
FAIL    PSS enforced on all namespaces (0/4 have baseline/restricted)
FAIL    memory limits set (17 containers without)
FAIL    seccomp RuntimeDefault by default (kubelet seccompDefault)
## Logs and auditing
FAIL    audit logging enabled
## Secrets
FAIL    encryption at rest for Secrets
INFO    14/14 Pods mount a ServiceAccount token (opt out where not needed)
PASS    no long-lived ServiceAccount token Secrets (0 found)
## Images
FAIL    images referenced by digest (10/18)
INFO    14/14 Pods not declaring runAsNonRoot
## Admission controllers
INFO    enabled: NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,...,ResourceQuota
INFO    webhooks: 0  ValidatingAdmissionPolicies: 0
```
That's expected for a single-user dev cluster. The point is knowing what you'd change for production:
| FAIL | Fix (lab) |
|---|---|
| system:masters kubeconfig | OIDC users + RBAC, admin cert only for break-glass ([hardening-guide/authentication-mechanisms](../hardening-guide/authentication-mechanisms/)) |
| no PSS | label namespaces, dry-run first ([pod-security-admission](../pod-security-admission/) Lab 3) |
| no memory limits | LimitRange defaults ([multi-tenancy](../multi-tenancy/)) |
| seccompDefault false | kubelet `seccompDefault: true` ([linux-kernel-security-constraints](../linux-kernel-security-constraints/)) |
| no audit / no encryption | API server flags ([secrets-good-practices](../secrets-good-practices/) shows encryption on a separate profile) |
| tags instead of digests | pin digests ([cloud-native-security](../cloud-native-security/) Lab 2) |

---

## Useful commands
```bash
./checklist.sh | grep -E '^(FAIL|MANUAL)'
kubectl get ns -L pod-security.kubernetes.io/enforce
```

## Cleanup
Nothing to clean up: the script only reads.
