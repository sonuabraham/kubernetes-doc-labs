# Configure a Security Context for a Pod or Container – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/

> Runs on the default **minikube** cluster, in the `default` namespace as in the docs.
> Docs examples, **verbatim**: [security-context.yaml](security-context.yaml), [security-context-2.yaml](security-context-2.yaml) …
> [security-context-6.yaml](security-context-6.yaml).
> The page only gives *snippets* for seccomp, AppArmor, SELinux, procMount and fsGroupChangePolicy. They are turned
> into runnable Pods here (not from the docs): [seccomp-pods.yaml](seccomp-pods.yaml) + [seccomp/](seccomp/),
> [apparmor-pods.yaml](apparmor-pods.yaml), [selinux-pod.yaml](selinux-pod.yaml), [procmount-pods.yaml](procmount-pods.yaml),
> [fsgroup-change-policy.yaml](fsgroup-change-policy.yaml), [security-context-3-root.yaml](security-context-3-root.yaml),
> [security-context-4-root.yaml](security-context-4-root.yaml). Helper: [fix-userns-sysfs.sh](fix-userns-sysfs.sh).
>
> **Differences from the page, found on 1.37 + minikube:**
> 1. `gcr.io/google-samples/hello-app:2.0` has **no shell** (`exec: "sh": executable file not found`) and now runs as
>    **uid 65532**. The docs' `exec … sh` steps don't work, and its capability bitmaps only show up in `CapBnd`.
> 2. minikube's node has AppArmor in the kernel, but the kubelet reports it as **not enabled**, so Pods that *explicitly* ask for AppArmor are rejected.
> 3. User-namespace Pods (needed for `procMount: Unmasked`) only start after [fix-userns-sysfs.sh](fix-userns-sysfs.sh).

## Key ideas (read first)

| Field | Level | What it does |
|---|---|---|
| `runAsUser` / `runAsGroup` | pod, container | UID / primary GID of the processes. Container values override pod values. Without `runAsGroup` the GID is 0. |
| `fsGroup` | pod | Extra supplementary group. Supported volumes are chown'ed to it, with setgid on directories. |
| `supplementalGroups` + `supplementalGroupsPolicy` | pod | More groups. `Merge` (default) **also adds groups from the image's `/etc/group`**. `Strict` uses only what the spec lists. The identity is reported in `status.containerStatuses[].user.linux`. |
| `fsGroupChangePolicy` | pod | `Always` walks the whole volume on every mount. `OnRootMismatch` walks it only if the volume root has the wrong owner or permissions. |
| `allowPrivilegeEscalation: false` | container | Sets `no_new_privs`: setuid binaries can't gain privileges. |
| `capabilities.add/drop` | container | Linux capabilities without the `CAP_` prefix. They only reach `CapEff` for **root** processes. |
| `seccompProfile` | pod, container | `RuntimeDefault`, `Unconfined`, or `Localhost` (a file under `<kubelet-root>/seccomp/`). With **no profile** you get Unconfined here, because kubelet `seccompDefault` is off. |
| `appArmorProfile` | pod, container | `RuntimeDefault`, `Unconfined`, or `Localhost` (a profile already loaded in the kernel). |
| `seLinuxOptions` | pod, container | MCS level/type. Has no effect on nodes without SELinux, like this one. |
| `procMount: Unmasked` | container | Don't mask `/proc/kcore` etc. or make `/proc/sys` read-only. Requires `hostUsers: false`. |

---

## Step 0
```bash
cd tasks/configure-pod-container/security-context
```

## Lab 1 – User, group, fsGroup (docs `security-context.yaml`)
```bash
kubectl apply -f security-context.yaml
kubectl exec security-context-demo -- sh -c 'ps; ls -l /data; cd /data/demo; echo hello > testfile; ls -l; id; grep -E "NoNewPrivs|^CapEff" /proc/1/status'
```
```
PID   USER     TIME  COMMAND
    1 1000      0:00 sleep 1h                          <- runAsUser
drwxrwsrwx    2 root     2000   4096 … demo            <- emptyDir group = fsGroup, setgid bit "s"
-rw-r--r--    1 1000     2000      6 … testfile        <- new files inherit group 2000
uid=1000 gid=3000 groups=2000,3000,4000                <- runAsGroup; fsGroup + supplementalGroups
CapEff:	0000000000000000                               <- non-root: no effective capabilities
NoNewPrivs:	1                                          <- allowPrivilegeEscalation: false
```
```bash
kubectl delete pod security-context-demo --now
```

## Lab 2 – Groups from the image's /etc/group (docs `-5`) and `Strict` (docs `-6`)
```bash
kubectl apply -f security-context-5.yaml
kubectl exec security-context-demo -- sh -c 'id; grep -E "1000|50000" /etc/group'
#   uid=1000(user-defined-in-image) gid=3000 groups=3000,4000,50000(group-defined-in-image)   <- 50000 came from the image
#   user-defined-in-image:x:1000:
#   group-defined-in-image:x:50000:user-defined-in-image
kubectl get pod security-context-demo -o jsonpath='{.status.containerStatuses[0].user}{"\n"}'
#   {"linux":{"gid":3000,"supplementalGroups":[3000,4000,50000],"uid":1000}}
kubectl delete pod security-context-demo --now

kubectl apply -f security-context-6.yaml          # supplementalGroupsPolicy: Strict
kubectl exec security-context-demo -- id
#   uid=1000(user-defined-in-image) gid=3000 groups=3000,4000          <- no 50000
kubectl get pod security-context-demo -o jsonpath='{.status.containerStatuses[0].user}{"\n"}'
#   {"linux":{"gid":3000,"supplementalGroups":[3000,4000],"uid":1000}}
kubectl get node minikube -o jsonpath='{.status.features}{"\n"}'
#   {"supplementalGroupsPolicy":true}                                <- containerd 2.x supports it
kubectl delete pod security-context-demo --now
```

## Lab 3 – Container overrides pod (docs `-2`)
```bash
kubectl apply -f security-context-2.yaml
kubectl exec -it security-context-demo-2 -- sh
#   error: … exec: "sh": executable file not found in $PATH         <- hello-app:2.0 is a shell-less image
kubectl debug security-context-demo-2 --image=busybox:1.36 --target=sec-ctx-demo-2 --container=dbg -q -- \
  sh -c 'sleep 1; ps -o user,pid,comm | head -3; grep ^Uid /proc/1/status'
kubectl logs security-context-demo-2 -c dbg
#   USER     PID   COMMAND
#   2000         1 hello-app           <- container runAsUser 2000 beats the pod's 1000
#   1000        22 sh                  <- the debug container inherits the POD-level 1000
```
`--target` puts the ephemeral container in the app's PID namespace, so `/proc/1` is the app.

## Lab 4 – Capabilities (docs `-3`, `-4`)
```bash
kubectl apply -f security-context-3.yaml -f security-context-4.yaml
for i in 3 4; do kubectl debug security-context-demo-$i --image=busybox:1.36 --target=sec-ctx-$i --container=dbg -q -- \
  grep -E '^(Uid|CapEff|CapBnd)' /proc/1/status; done
sleep 5; for i in 3 4; do echo "== demo-$i"; kubectl logs security-context-demo-$i -c dbg; done
```
```
== demo-3                                  == demo-4
Uid:    65532 65532 65532 65532            Uid:    65532 …
CapEff: 0000000000000000                   CapEff: 0000000000000000      <- non-root: empty
CapBnd: 00000000a80425fb                   CapBnd: 00000000aa0435fb      <- the docs' two values
```
The image runs as non-root uid 65532, so the capabilities stay in the bounding set and never become effective.
To see the docs' `CapPrm/CapEff`, run the same thing as root (busybox):
```bash
kubectl apply -f security-context-3-root.yaml -f security-context-4-root.yaml
for p in 3 4; do kubectl exec security-context-demo-$p-root -- grep -E '^Cap(Prm|Eff)' /proc/1/status; done
#   CapPrm/CapEff: 00000000a80425fb          (default set)
#   CapPrm/CapEff: 00000000aa0435fb          (+ NET_ADMIN bit 12, + SYS_TIME bit 25)
python3 -c "
n='CHOWN DAC_OVERRIDE DAC_READ_SEARCH FOWNER FSETID KILL SETGID SETUID SETPCAP LINUX_IMMUTABLE NET_BIND_SERVICE NET_BROADCAST NET_ADMIN NET_RAW IPC_LOCK IPC_OWNER SYS_MODULE SYS_RAWIO SYS_CHROOT SYS_PTRACE SYS_PACCT SYS_ADMIN SYS_BOOT SYS_NICE SYS_RESOURCE SYS_TIME SYS_TTY_CONFIG MKNOD LEASE AUDIT_WRITE AUDIT_CONTROL SETFCAP'.split()
print(' '.join(x for i,x in enumerate(n) if 0xa80425fb>>i&1))"
#   CHOWN DAC_OVERRIDE FOWNER FSETID KILL SETGID SETUID SETPCAP NET_BIND_SERVICE NET_RAW SYS_CHROOT MKNOD AUDIT_WRITE SETFCAP
for p in 3 4; do kubectl exec security-context-demo-$p-root -- sh -c 'ip link set lo mtu 1400 && echo mtu changed'; done
#   ip: SIOCSIFMTU: Operation not permitted     <- no NET_ADMIN
#   mtu changed                                 <- NET_ADMIN (only the Pod's own network namespace)
kubectl exec security-context-demo-3-root -- date -s 2020-01-01
#   date: can't set date: Operation not permitted
```
⚠️ **Don't** run `date -s` in `security-context-demo-4-root`. The clock isn't namespaced, so `SYS_TIME` really changes
the **node's** clock for every Pod. That's why it is a dangerous capability.

## Lab 5 – Seccomp (not from the docs)
Put the two Localhost profiles under the kubelet's seccomp directory on the node:
```bash
minikube ssh -- "sudo mkdir -p /var/lib/kubelet/seccomp/my-profiles"
for f in profile-allow.json profile-deny-mkdir.json; do minikube cp seccomp/my-profiles/$f /var/lib/kubelet/seccomp/my-profiles/$f; done
kubectl apply -f seccomp-pods.yaml
for p in seccomp-none seccomp-runtimedefault seccomp-unconfined seccomp-localhost-allow seccomp-localhost-deny-mkdir; do
  echo "$p: $(kubectl exec $p -- sh -c 'grep Seccomp: /proc/1/status; mkdir /tmp/x 2>&1 && echo mkdir-ok; unshare -U true 2>&1 && echo unshare-ok' | tr '\n' ' ')"; done
```
| Pod | `Seccomp:` | mkdir | `unshare -U` |
|---|---|---|---|
| seccomp-none | 0 (off) | ok | ok. **No profile means unconfined** (kubelet `seccompDefault: false`). |
| seccomp-runtimedefault | 2 (filter) | ok | `Operation not permitted`: containerd's default profile blocks it |
| seccomp-unconfined | 0 | ok | ok |
| seccomp-localhost-allow (`my-profiles/profile-allow.json`, docs path) | 2 | ok | ok (`SCMP_ACT_LOG`: allows and logs everything) |
| seccomp-localhost-deny-mkdir | 2 | `can't create directory '/tmp/x': Operation not permitted` | ok |
| seccomp-localhost-missing | – | `CreateContainerError`: `cannot load seccomp profile "/var/lib/kubelet/seccomp/my-profiles/does-not-exist.json"` | |

## Lab 6 – AppArmor (not from the docs)
```bash
kubectl apply -f apparmor-pods.yaml
kubectl get pods | grep apparmor
#   apparmor-default          1/1   Running        <- field not set: admitted, unconfined
#   apparmor-runtimedefault   0/1   AppArmor       <- explicitly RuntimeDefault: rejected
#   apparmor-unconfined       1/1   Running
#   apparmor-localhost        0/1   AppArmor
kubectl describe pod apparmor-runtimedefault | grep Warning
#   Warning  AppArmor  kubelet  Cannot enforce AppArmor: AppArmor is not enabled on the host
minikube ssh -- cat /sys/module/apparmor/parameters/enabled
#   Y          <- the host kernel has AppArmor, but the kubelet inside the minikube container can't use it
```
This is the docs' note, measured. An explicit `RuntimeDefault` is refused on a node without (usable) AppArmor.
The implicit default is skipped silently. On a node with AppArmor, `apparmor-localhost` additionally needs the profile
loaded with `apparmor_parser` (see the AppArmor tutorial).

## Lab 7 – SELinux (not from the docs)
```bash
kubectl apply -f selinux-pod.yaml           # seLinuxOptions.level: "s0:c123,c456"
kubectl get pod selinux-demo                # Running - accepted…
minikube ssh -- ls /sys/fs/selinux          # No such file or directory - …and ignored: no SELinux on this node
```
On SELinux nodes (RHEL/Fedora), PVC volumes get the label at mount time (`-o context=`) if the CSIDriver says `seLinuxMount: true`.
`SELinuxMount` is GA in 1.37. Pods sharing such a volume with *different* labels then need
`seLinuxChangePolicy: Recursive`. The csi-hostpath driver here has `seLinuxMount: false`.

## Lab 8 – fsGroupChangePolicy on a real PV (not from the docs)
```bash
run(){ kubectl apply -f fsgroup-change-policy.yaml -l role=$1 >/dev/null
       kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/fsgroup-$1 --timeout=90s >/dev/null
       echo "== $1"; kubectl logs fsgroup-$1 | grep -vE '^total|^$'; kubectl delete pod fsgroup-$1 --now >/dev/null; }
kubectl apply -f fsgroup-change-policy.yaml -l role=pvc
for r in writer tamper onroot always; do run $r; done
```
```
== writer      -rw-r--r-- 1000 2000 a  |  drwxr-sr-x 1000 2000 sub  |  -rw-r--r-- 1000 2000 sub/b
== tamper      … sub/b group set back to 0 (root dir untouched)
== onroot      -rw-r--r-- 1000 2000 a  |  drwxr-sr-x 1000 2000 sub  |  -rw-r--r-- 1000 0    sub/b   <- root matched: NOT walked
== always      -rw-rw-r-- 1000 2000 a  |  drwxrwsr-x 1000 2000 sub  |  -rw-rw-r-- 1000 2000 sub/b   <- walked: fixed + group rw
```
`OnRootMismatch` is fast for big volumes, but files changed behind its back stay as they are.

## Lab 9 – procMount (not from the docs; needs user namespaces)
```bash
kubectl apply -f procmount-pods.yaml
#   The Pod "procmount-unmasked-hostusers" is invalid: … procMount: Invalid value: "Unmasked": `hostUsers` must be false to use `Unmasked`
kubectl get pods | grep procmount
#   procmount-default    0/1   ContainerCreating     <- the two hostUsers:false Pods hang on minikube:
kubectl describe pod procmount-default | grep FailedCreatePodSandBox | tail -1
#   … error mounting "sysfs" to rootfs at "/sys": … operation not permitted
./fix-userns-sysfs.sh                                  # see the script header for why
#   dmi overmounts left: 0
kubectl delete -f procmount-pods.yaml --now; kubectl apply -f procmount-pods.yaml
for p in procmount-default procmount-unmasked; do echo "== $p"; kubectl exec $p -- sh -c \
  'echo "masking submounts: $(grep -cE " /proc/| /sys/firmware" /proc/self/mountinfo)"; mount | grep " /proc/sys "; cat /proc/self/uid_map'; done
```
```
== procmount-default
masking submounts: 14                                   <- kcore, keys, timer_list… covered; acpi, scsi as empty tmpfs
proc on /proc/sys type proc (ro,nosuid,nodev,noexec,relatime)
         0 1206648832      65536                        <- root in the Pod = uid 1206648832 on the node
== procmount-unmasked
masking submounts: 0
         0 1407451136      65536
```

## Useful commands
```bash
kubectl explain pod.spec.securityContext ; kubectl explain pod.spec.containers.securityContext
kubectl exec <pod> -- grep -E '^(Uid|Gid|Groups|Cap|NoNewPrivs|Seccomp)' /proc/1/status
kubectl debug <pod> --image=busybox --target=<ctr> -- cat /proc/1/status     # for shell-less images
```

## Cleanup
```bash
./cleanup.sh      # all Pods + PVC, and the seccomp profiles on the node (the sysfs fix goes away on the next node restart)
```
