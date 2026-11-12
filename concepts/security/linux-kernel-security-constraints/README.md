# Linux Kernel Security Constraints for Pods and Containers – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/linux-kernel-security-constraints/

> A concepts page (no YAML). [01-pods.yaml](01-pods.yaml) runs the same busybox with different constraints, and a probe measures what each can do. [deny-mkdir.json](deny-mkdir.json) is a custom **Localhost** seccomp profile.

## Key ideas (read first)

| Mechanism | What it limits | Pod field |
|---|---|---|
| **Non-root** | UID/GID of the process; file permissions do the rest | `runAsUser`, `runAsGroup`, `runAsNonRoot`, `fsGroup` |
| **Capabilities** | Slices of root power (`CAP_CHOWN`, `CAP_NET_ADMIN`, `CAP_SYS_ADMIN`…) | `capabilities.drop/add` (drop `ALL`) |
| **seccomp** | Which **syscalls** may be made (filter) | `seccompProfile: RuntimeDefault \| Localhost \| Unconfined`. kubelet `seccompDefault: true` makes RuntimeDefault the default. |
| **AppArmor** | Path-based MAC: files, capabilities, network per **profile** (Debian/Ubuntu/SUSE) | `appArmorProfile` |
| **SELinux** | Label-based MAC: types and MCS categories (RHEL/Fedora) | `seLinuxOptions` |
| **no_new_privs** | setuid binaries can't escalate | `allowPrivilegeEscalation: false` |
| **Privileged** | Turns most of the above **off**: all capabilities, all devices, no seccomp/AppArmor confinement | `privileged: true` (avoid) |
| **Managing profiles** | Custom seccomp/AppArmor profiles must exist **on every node** (seccomp: `<kubelet root>/seccomp/`). Use operators (Security Profiles Operator) to distribute them. | |

---

## Step 1
```bash
cd concepts/security/linux-kernel-security-constraints
minikube ssh -- "sudo mkdir -p /var/lib/kubelet/seccomp/profiles"
minikube cp deny-mkdir.json /var/lib/kubelet/seccomp/profiles/deny-mkdir.json     # must be on the NODE
kubectl create ns kern-demo ; kubectl apply -n kern-demo -f 01-pods.yaml
```

## Lab 1 – Same image, different constraints
```bash
for p in default runtime-default localhost-seccomp restricted privileged; do kubectl exec $p -n kern-demo -- sh -c '
  echo "$(id -u) $(grep Seccomp: /proc/self/status | cut -f2) $(grep CapEff /proc/self/status | cut -f2) \
  mkdir:$(mkdir /dev/shm/x$$ 2>/dev/null && echo ok || echo DENIED) chown:$(chown 123 /dev/shm 2>/dev/null && echo ok || echo DENIED) \
  mount:$(mount -t tmpfs t /dev/shm 2>/dev/null && echo ok || echo DENIED) unshare-U:$(unshare -U true 2>/dev/null && echo ok || echo DENIED)"' ; done
```
Measured:
```
POD                UID    SECCOMP  CAPEFF            MKDIR    CHOWN    MOUNT    UNSHARE-U
default            0      0        00000000a80425fb  ok       ok       DENIED   ok        <- seccomp OFF by default on this kubelet!
runtime-default    0      2        00000000a80425fb  ok       ok       DENIED   DENIED    <- containerd's default filter blocks unshare(CLONE_NEWUSER)
localhost-seccomp  0      2        00000000a80425fb  DENIED   ok       DENIED   ok        <- our profile: only mkdir/mkdirat → EPERM
restricted         1000   2        0000000000000000  ok       DENIED   DENIED   DENIED    <- non-root, no capabilities: chown fails
privileged         0      0        000001ffffffffff  ok       ok       ok       ok        <- all 41 capabilities, can mount
```
- `Seccomp: 0` = disabled, `2` = filter mode.
- `a80425fb` is the runtime's default capability set (CHOWN, DAC_OVERRIDE, FOWNER, FSETID, KILL, SETGID, SETUID, SETPCAP, NET_BIND_SERVICE, NET_RAW, SYS_CHROOT, MKNOD, AUDIT_WRITE, SETFCAP). Decode with `capsh --decode=00000000a80425fb`.
- The default container can't mount (no `CAP_SYS_ADMIN`). Privileged can.
```bash
kubectl get --raw /api/v1/nodes/minikube/proxy/configz | jq -c '.kubeletconfig | {seccompDefault}'
#   {"seccompDefault":false}           <- why "default" ran unconfined; set true on real nodes
```

## Lab 2 – AppArmor on minikube
```bash
kubectl get pod apparmor -n kern-demo -o jsonpath='{.status.reason}: {.status.message}'
#   AppArmor: Pod was rejected: Cannot enforce AppArmor: AppArmor is not enabled on the host
minikube ssh -- "cat /sys/module/apparmor/parameters/enabled"     # Y  - the HOST kernel has it...
```
...but the kubelet inside the minikube **container** can't use it (securityfs isn't available to it), so containers report `runc (unconfined)` and any Pod *requesting* AppArmor is **rejected** rather than silently unconfined. That's the safe failure mode. SELinux isn't present at all (Ubuntu host). On a real Ubuntu node, `RuntimeDefault` gives the `cri-containerd.apparmor.d` profile.

---

## Useful commands
```bash
kubectl exec <pod> -- grep -E 'Seccomp|CapEff|NoNewPrivs' /proc/self/status
kubectl exec <pod> -- cat /proc/self/attr/current          # AppArmor / SELinux label
kubectl get --raw /api/v1/nodes/<n>/proxy/configz | jq '.kubeletconfig.seccompDefault'
```

## Cleanup
```bash
./cleanup.sh       # namespace + the node's seccomp profile file
```
