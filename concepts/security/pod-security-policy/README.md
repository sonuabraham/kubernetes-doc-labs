# Pod Security Policies (removed) – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/pod-security-policy/

> **PodSecurityPolicy was deprecated in v1.21 and removed in v1.25.** The page only points to the replacements. This lab proves the API is gone and walks through a typical **migration** of a "restricted" PSP to Pod Security Admission plus a ValidatingAdmissionPolicy.

## Key ideas (read first)

| | PodSecurityPolicy (gone) | Pod Security Admission (built in) | ValidatingAdmissionPolicy / 3rd party |
|---|---|---|---|
| Scope | Cluster objects, chosen via **RBAC `use`** on the policy (confusing, hard to audit) | Namespace **labels** | Any match expression |
| Flexibility | Many knobs, and could **mutate** (defaults) | Three fixed levels | Arbitrary rules (CEL; Kyverno/Gatekeeper can mutate) |
| Modes | enforce only | enforce / warn / audit | Deny / Warn / Audit |

Migration path: map each PSP to the closest PSS level → label namespaces (start with `warn`/`audit`) → express what's left (e.g. `readOnlyRootFilesystem`, image registries, mutation) with ValidatingAdmissionPolicy, Kyverno, Gatekeeper… See [../pod-security-admission](../pod-security-admission/).

---

## Lab 1 – The API is gone
```bash
cd concepts/security/pod-security-policy
kubectl api-resources | grep -i podsecuritypolic || echo "no PodSecurityPolicy resource"
kubectl apply -f 00-legacy-psp.yaml
#   no matches for kind "PodSecurityPolicy" in version "policy/v1beta1"
```

## Lab 2 – Migrate the legacy "restricted" PSP
| PSP field in [00-legacy-psp.yaml](00-legacy-psp.yaml) | Replacement |
|---|---|
| privileged, allowPrivilegeEscalation, requiredDropCapabilities ALL, host namespaces, volumes, MustRunAsNonRoot | PSA `restricted` |
| fsGroup / supplementalGroups `MustRunAs` ranges | (PSA doesn't check them; mutation via a policy engine if needed) |
| **readOnlyRootFilesystem: true** | **ValidatingAdmissionPolicy** (CEL) |
```bash
kubectl apply -f 01-migrated.yaml      # namespace (PSA restricted, pinned v1.37) + VAP + binding
P='{"apiVersion":"v1","kind":"Pod","metadata":{"name":"app"},"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"c","image":"busybox:1.36","command":["sleep","3600"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
echo "$P" | kubectl apply -n psp-migrated -f -
#   ValidatingAdmissionPolicy 'require-readonly-rootfs' ... denied request: all containers must set securityContext.readOnlyRootFilesystem: true
echo "$P" | jq '.spec.containers[0].securityContext.readOnlyRootFilesystem=true' | kubectl apply -n psp-migrated -f -        # created
echo "$P" | jq '.spec.containers[0].securityContext.readOnlyRootFilesystem=true | .spec.hostNetwork=true | .metadata.name="app2"' | kubectl apply -n psp-migrated -f -
#   violates PodSecurity "restricted:v1.37": host namespaces (hostNetwork=true)     <- PSA covers the rest
kubectl exec app -n psp-migrated -- touch /x          # touch: /x: Read-only file system
```

---

## Useful commands
```bash
kubectl get validatingadmissionpolicies,validatingadmissionpolicybindings
kubectl label --dry-run=server --overwrite ns --all pod-security.kubernetes.io/enforce=baseline
```

## Cleanup
```bash
./cleanup.sh
```
