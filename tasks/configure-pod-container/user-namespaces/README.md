# Use a User Namespace With a Pod – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/user-namespaces/

> Runs on the default **minikube** cluster (containerd 2.3, runc 1.4, kernel 7.0: all requirements met), **after**
> [../security-context/fix-userns-sysfs.sh](../security-context/fix-userns-sysfs.sh). Without it, every `hostUsers: false`
> Pod hangs in `ContainerCreating` (Step 0 shows why). The fix lasts until the node restarts.
> Files: [user-namespaces-stateless.yaml](user-namespaces-stateless.yaml) (docs, **verbatim**). Not from the docs:
> [userns-hostpath.yaml](userns-hostpath.yaml), [userns-write.yaml](userns-write.yaml).
> Concepts: [concepts/workloads/pods/user-namespaces](../../../concepts/workloads/pods/user-namespaces/).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`hostUsers: false`** | The Pod gets its own user namespace. uid 0…65535 inside map to a unique 65536-sized range on the node (`/proc/self/uid_map`). |
| **What it protects** | Processes: root in the Pod is an unprivileged uid on the node, so a container breakout lands as "nobody special", and capabilities only count inside the namespace. Each Pod gets a different range, so Pods can't touch each other's processes or files either. |
| **What it doesn't** | **Volumes are idmapped mounts.** Files appear with their real owners, and container root acts as owner 0 on them. A `hostPath` of root-only files is still readable and writable. |
| **Forbidden together** | `hostNetwork`, `hostPID`, `hostIPC`. **Allowed:** `privileged: true` (privileged *inside* the namespace) and `procMount: Unmasked`. |
| **Pod Security** | `restricted` doesn't require `runAsNonRoot` for `hostUsers: false` Pods. Root inside a user namespace is acceptable. |
| **Filesystem support** | idmapped mounts need support from the filesystem: the node's overlayfs `/` fails, ext4 `/var` works. |

---

## Step 0 – Why it hangs on minikube, and the fix
```bash
cd tasks/configure-pod-container/user-namespaces
kubectl apply -f user-namespaces-stateless.yaml
kubectl get pod userns                   # ContainerCreating … forever
kubectl get events --field-selector involvedObject.name=userns,reason=FailedCreatePodSandBox -o jsonpath='{.items[0].message}'
#   … error mounting "sysfs" to rootfs at "/sys": … operation not permitted
../security-context/fix-userns-sysfs.sh
#   dmi overmounts left: 0
kubectl wait --for=condition=Ready pod/userns       # Running ~15 s later (the kubelet retries the sandbox)
```

## Lab 1 – Inside vs outside (docs)
```bash
kubectl exec userns -- readlink /proc/self/ns/user       # user:[4026533946]
kubectl exec userns -- cat /proc/self/uid_map            #          0 1326514176      65536
kubectl exec userns -- id                                # uid=0(root) gid=0(root)
minikube ssh -- 'readlink /proc/self/ns/user; cat /proc/self/uid_map; sudo readlink /proc/$(pidof kubelet)/ns/user'
#   user:[4026531837]                        <- different namespace: the initial one
#            0          0 4294967295         <- the host maps everything
#   user:[4026531837]                        <- the kubelet is NOT in a user namespace (so no extra comparison needed)
minikube ssh -- 'P=$(pgrep -f "sleep infinity" | head -1); grep -E "^Uid" /proc/$P/status'
#   Uid:  1326514176 …                       <- "root" of the Pod, as the node sees it
```

## Lab 2 – Every Pod gets its own range (not from the docs)
```bash
sed 's/name: userns/name: userns-2/' user-namespaces-stateless.yaml | kubectl apply -f -
for p in userns userns-2; do echo "$p: $(kubectl exec $p -- cat /proc/self/uid_map)"; done
#   userns:            0 1326514176      65536
#   userns-2:          0 1356201984      65536
kubectl exec userns -- sh -c 'echo 1 > /proc/sys/kernel/sysrq; ls -l /proc/sys/kernel/sysrq'
#   cannot create /proc/sys/kernel/sysrq: Read-only file system
#   -rw-r--r-- 1 nobody nogroup …            <- host-root-owned files show up as the overflow user "nobody"
```

## Lab 3 – What user namespaces do NOT protect: hostPath (not from the docs)
```bash
minikube ssh -- "sudo mkdir -p /var/lab-root-only && echo top-secret | sudo tee /var/lab-root-only/secret >/dev/null \
  && sudo chmod 700 /var/lab-root-only && sudo chmod 600 /var/lab-root-only/secret"
kubectl apply -f userns-hostpath.yaml
for p in hostpath-hostusers hostpath-userns; do echo "== $p"; kubectl logs $p; done
#   == hostpath-hostusers   uid=0(root) …  top-secret
#   == hostpath-userns      uid=0(root) …  top-secret      <- readable too!
kubectl apply -f userns-write.yaml; kubectl logs hostpath-userns-write
minikube ssh -- "sudo ls -ln /var/lab-root-only"
#   -rw-r--r-- 1 0 0 3 … from-userns-pod     <- written as REAL uid 0 on the node
```
The kubelet mounts volumes with an **idmap**: host ids 0…65535 become container ids 0…65535 for that mount, so files
keep working as if there were no user namespace. Keep restricting `hostPath` with Pod Security / admission policy.
A first try used the node's `/root`, and the container failed with `StartError: failed to set MOUNT_ATTR_IDMAP on /root:
invalid argument`. The node's root filesystem is overlayfs, which can't be idmapped. `/var` is ext4.

## Lab 4 – Allowed and forbidden combinations (not from the docs)
```bash
t(){ printf '%-22s ' "$1"; kubectl create --dry-run=server -o name -f <(kubectl create --dry-run=client -o json \
     -f user-namespaces-stateless.yaml | jq ".metadata.name=\"userns-test\" | $2") 2>&1 | cut -c1-120; }
t hostNetwork '.spec.hostNetwork=true'     # spec.hostNetwork: Forbidden: when `hostUsers` is false
t hostPID     '.spec.hostPID=true'         # spec.HostPID: Forbidden: when `hostUsers` is false
t hostIPC     '.spec.hostIPC=true'         # spec.HostIPC: Forbidden: when `hostUsers` is false
t privileged  '.spec.containers[0].securityContext={privileged:true}'    # pod/userns-test  (allowed)
```
Pod Security `restricted`, running as root:
```bash
kubectl create ns userns-restricted; kubectl label ns userns-restricted pod-security.kubernetes.io/enforce=restricted
```
| Pod (runs as root; drop ALL, no privilege escalation, seccomp RuntimeDefault) | Result |
|---|---|
| `hostUsers: false` | **admitted** |
| `hostUsers: true` | `violates PodSecurity "restricted:latest": runAsNonRoot != true …` |

## Useful commands
```bash
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.hostUsers==false) | .metadata.namespace+"/"+.metadata.name'
kubectl exec <pod> -- cat /proc/self/uid_map
```

## Cleanup
```bash
./cleanup.sh       # Pods, the test namespace, /var/lab-root-only on the node
```
