# Security – Hands-on Labs

Based on: https://kubernetes.io/docs/concepts/security/

> Every page in this section has a lab folder. Several of them change API-server flags, and those run on **separate minikube profiles** (`enc-lab` for encryption at rest) so the main cluster stays untouched.

## The map

| Layer | Pages (labs) |
|---|---|
| **Big picture** | [cloud-native-security](cloud-native-security/) (lifecycle phases + read-only cluster audit), [security-checklist](security-checklist/) (automated cluster checklist), [application-security-checklist](application-security-checklist/) (hardened app + linter) |
| **API access** | [controlling-access](controlling-access/) (a request through TLS → authn → authz → admission, with a real x509 user), [service-accounts](service-accounts/), [rbac-good-practices](rbac-good-practices/) (11 escalation paths, reproduced), [hardening-guide/authentication-mechanisms](hardening-guide/authentication-mechanisms/) |
| **Pod isolation** | [pod-security-standards](pod-security-standards/) (control matrix), [pod-security-admission](pod-security-admission/) (modes, versions, migration), [pod-security-policy](pod-security-policy/) (removed → PSA + ValidatingAdmissionPolicy), [linux-kernel-security-constraints](linux-kernel-security-constraints/) (seccomp, capabilities, AppArmor), [linux-security](linux-security/) (tmpfs noswap), [windows-security](windows-security/) |
| **Data** | [secrets-good-practices](secrets-good-practices/) (encryption at rest on `enc-lab`) |
| **Tenancy** | [multi-tenancy](multi-tenancy/) (namespace-per-tenant kit, incl. the tenant admin deleting its own NetworkPolicy) |
| **Below the API** | [api-server-bypass-risks](api-server-bypass-risks/) (static Pod vs PSA, kubelet, etcd, containerd socket) |
| **Components** | [hardening-guide/scheduler](hardening-guide/scheduler/), [hardening-guide/dynamic-resource-allocation](hardening-guide/dynamic-resource-allocation/) |

## Findings worth remembering (measured on minikube v1.37)

| Finding | Lab |
|---|---|
| Pods run **seccomp-unconfined** by default (`seccompDefault: false`); AppArmor requests are **rejected** on the docker driver | linux-kernel-security-constraints |
| Secrets are **plaintext in etcd** until encryption at rest, and old ones stay plaintext until rewritten | ../configuration/secret, secrets-good-practices |
| `list secrets` = read secrets; `create pods` = read secrets and borrow any SA in the namespace | rbac-good-practices |
| The built-in `admin` role can delete NetworkPolicies, so a tenant can un-isolate itself | multi-tenancy |
| A static Pod runs privileged in a `restricted` namespace; only its mirror is rejected | api-server-bypass-risks |
| kindnet **does** enforce NetworkPolicy | multi-tenancy, application-security-checklist |
| The docs' "my-scheduler" config doesn't start (queueSort must keep one plugin) | hardening-guide/scheduler |

## Quick posture check
```bash
cd concepts/security
cloud-native-security/audit.sh            # by lifecycle phase
security-checklist/checklist.sh           # PASS/FAIL against the checklist
```
