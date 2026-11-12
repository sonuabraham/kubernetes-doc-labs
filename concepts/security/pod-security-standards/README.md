# Pod Security Standards – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/pod-security-standards/

> The page defines policies, not manifests. This lab measures **every control** against the built-in enforcement (Pod Security Admission, see [../pod-security-admission](../pod-security-admission/)): [matrix.sh](matrix.sh) starts from a Restricted-compliant Pod, breaks one control at a time, and server-dry-runs it into three namespaces.

## Key ideas (read first)

| Profile | Intent | For |
|---|---|---|
| **Privileged** | Unrestricted, allows known privilege escalations | System and infrastructure workloads run by trusted admins |
| **Baseline** | Minimally restrictive. Blocks **known privilege escalations**, allows the default Pod | Most ordinary apps, with easy adoption |
| **Restricted** | Heavily restricted, current hardening **best practice** | Security-critical apps, lower-trust users |

| Concept | Meaning |
|---|---|
| **Cumulative** | Restricted = Baseline + more. Privileged = nothing checked. |
| **Policy vs mechanism** | The standards are just definitions. Enforce them with PSA (built in), or Kyverno, OPA Gatekeeper, ValidatingAdmissionPolicy… |
| **Versioned** | `restricted:v1.37` pins the rules of that release. `latest` follows upgrades. |
| **Pod OS** | With `spec.os.name: windows`, Linux-only Restricted checks (seccomp, capabilities…) are skipped. With `linux`, Windows-only checks are skipped. |
| **User namespaces** (`hostUsers: false`) | Restricted no longer requires `runAsNonRoot` / non-zero `runAsUser`: root in the Pod isn't root on the node. |
| **Security context vs profile** | A security context **configures** one Pod. A profile **validates** Pods against a standard. |
| **Sandboxed Pods** (gVisor, Kata) | No separate profile: isolation is a different axis. Still apply a standard. |

---

## Lab 1 – The control matrix
```bash
cd concepts/security/pod-security-standards
kubectl apply -f 00-namespaces.yaml       # pss-privileged / pss-baseline / pss-restricted (enforce labels)
./matrix.sh
```
Measured on v1.37:
```
CONTROL                                    privileged  baseline    restricted
compliant (restricted)                     allowed     allowed     allowed
hostNetwork                                allowed     DENIED      DENIED      <- Baseline: host namespaces
hostPID                                    allowed     DENIED      DENIED
hostIPC                                    allowed     DENIED      DENIED
privileged                                 allowed     DENIED      DENIED      <- privileged containers
capabilities.add NET_ADMIN                 allowed     DENIED      DENIED      <- capabilities beyond the default set
capabilities.add CHOWN (baseline list)     allowed     allowed     DENIED      <- Restricted: only NET_BIND_SERVICE may be added
capabilities.add NET_BIND_SERVICE          allowed     allowed     allowed
hostPath volume                            allowed     DENIED      DENIED
hostPort                                   allowed     DENIED      DENIED
appArmor Unconfined                        allowed     DENIED      DENIED
seLinux custom type                        allowed     DENIED      DENIED      <- only container_t / container_init_t / container_kvm_t / container_engine_t
procMount Unmasked (+hostUsers:false)      allowed     allowed     DENIED      <- Baseline allows it for user-namespaced Pods
seccomp Unconfined                         allowed     DENIED      DENIED
unsafe sysctl                              allowed     DENIED      DENIED
safe sysctl                                allowed     allowed     allowed      <- e.g. net.ipv4.ip_unprivileged_port_start
emptyDir/configMap volumes                 allowed     allowed     allowed
nfs volume (non-core type)                 allowed     allowed     DENIED      <- Restricted: only configMap, csi, downwardAPI, emptyDir, ephemeral, image, PVC, projected, secret
no allowPrivilegeEscalation:false          allowed     allowed     DENIED
no runAsNonRoot                            allowed     allowed     DENIED
runAsUser 0                                allowed     allowed     DENIED
no seccompProfile                          allowed     allowed     DENIED      <- must be RuntimeDefault or Localhost
capabilities not dropping ALL              allowed     allowed     DENIED
no runAsNonRoot + hostUsers:false          allowed     allowed     allowed      <- user-namespace relaxation
plain pod, no securityContext              allowed     allowed     DENIED      <- the default Pod passes Baseline, not Restricted
```
Two first attempts came back as **API validation** errors, not PSA: `privileged: true` together with `allowPrivilegeEscalation: false` is contradictory, and `procMount: Unmasked` requires `hostUsers: false`. The script marks such cases `INVALID`.

## Lab 2 – Read the denial
```bash
kubectl run plain -n pss-restricted --image=busybox:1.36 --dry-run=server
#   Error from server (Forbidden): pods "plain" is forbidden: violates PodSecurity "restricted:latest":
#   allowPrivilegeEscalation != false (container "plain" must set securityContext.allowPrivilegeEscalation=false),
#   unrestricted capabilities (container "plain" must set securityContext.capabilities.drop=["ALL"]),
#   runAsNonRoot != true (...), seccompProfile (...)
```
One message lists **every** failing control with the fix.

## Lab 3 – A compliant Pod actually runs
```bash
kubectl apply -n pss-restricted -f 01-restricted-compliant.yaml
kubectl logs restricted-ok -n pss-restricted        # uid=1000 gid=0(root) groups=0(root)
```
Many images assume root (nginx on port 80, apt…), so Restricted usually means choosing non-root images (`nginxinc/nginx-unprivileged`, distroless `:nonroot`).

## Lab 4 – Pod OS field
```bash
W='{"apiVersion":"v1","kind":"Pod","metadata":{"name":"w"},"spec":{"os":{"name":"windows"},"securityContext":{"runAsNonRoot":true,"windowsOptions":{"runAsUserName":"ContainerUser"}},"containers":[{"name":"c","image":"mcr.microsoft.com/windows/nanoserver:ltsc2022"}]}}'
echo "$W" | kubectl apply -n pss-restricted --dry-run=server -f -      # created (server dry run)
```
No seccomp, no capability drop, no allowPrivilegeEscalation, yet Restricted passes because those checks are Linux-only. Without `os.name: windows` the same Pod is denied for exactly those fields. (Setting `allowPrivilegeEscalation` on a Windows Pod is itself an API error.)

---

## Useful commands
```bash
kubectl label ns <ns> pod-security.kubernetes.io/enforce=baseline
kubectl run x -n <ns> --image=busybox --dry-run=server          # quick policy probe
kubectl get ns -L pod-security.kubernetes.io/enforce
```

## Cleanup
```bash
./cleanup.sh
```
