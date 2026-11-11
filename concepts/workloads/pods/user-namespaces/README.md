# User Namespaces – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/user-namespaces/

> ⚠️ **On minikube's docker driver, user-namespaced Pods can't start.** Your machine meets every listed requirement (kernel 7.0, runc 1.4.3, containerd 2.3, `UserNamespacesSupport` on), but minikube's node is itself a Docker container, and runc fails with `error mounting "sysfs" to rootfs at "/sys": … operation not permitted`. The API-side behaviour (Labs 3–4) works. For Labs 1–2 use a VM-based cluster: `minikube start -p userns --driver=kvm2` (needs libvirt) or a real node.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **User namespace** | Maps users in the container to **different users on the host**: root (UID 0) inside becomes an unprivileged high UID outside. A container escape then lands as a nobody. Several HIGH/CRITICAL CVEs weren't exploitable with it. |
| **Opt in** | `spec.hostUsers: false`. The kubelet picks a non-overlapping host UID/GID range per Pod (65536 IDs each, above 65535; configurable with `userNamespaces.idsPerPod`, a multiple of 65536). |
| **Capabilities** | Valid only inside the namespace. `CAP_SYS_MODULE` does nothing, and `CAP_SYS_ADMIN` is namespace-local. |
| **Volumes** | `runAsUser` etc. refer to the **in-container** users, and **idmap mounts** keep file ownership in volumes as if userns were off. |
| **Requirements** | Linux ≥ 6.3 (tmpfs idmap), filesystems with idmap support, runc ≥ 1.2 / crun ≥ 1.9, containerd ≥ 2.0 / CRI-O ≥ 1.25. NFS volumes are **not** supported. |
| **Custom ID range** | A `kubelet` user, `getsubids`, and `/etc/subuid` + `/etc/subgid` with one line such as `kubelet:65536:7208960`. Must be a multiple of 65536, ≥ 65536, and at least 65536 × maxPods. |
| **Not allowed with it** | `hostNetwork`, `hostIPC`, `hostPID`, `volumeDevices`. |
| **Pod Security** | With `hostUsers: false`, the **Baseline/Restricted** checks for `runAsNonRoot` and `runAsUser` (and Baseline `procMount`) are **relaxed**, because root inside isn't root. |
| **Metrics** | kubelet: `started_user_namespaced_pods_total`, `…_errors_total`. |

## The demo app
| File | What |
|---|---|
| [kubelet-idsperpod-excerpt.yaml](kubelet-idsperpod-excerpt.yaml) | The docs' `idsPerPod: 1048576` KubeletConfiguration, **verbatim** |
| [subuid-subgid-example.txt](subuid-subgid-example.txt) | The docs' `kubelet:65536:7208960` line |
| [00-userns-pods.yaml](00-userns-pods.yaml) | `with-userns` (hostUsers false) and `without-userns`, both running as root |
| [01-userns-with-hostnetwork.yaml](01-userns-with-hostnetwork.yaml) | an invalid combination |
| [02-restricted-namespace.yaml](02-restricted-namespace.yaml) | a Restricted-PSS namespace + a root pod using userns |

---

## Lab 1 – Root inside, nobody outside (needs a VM-based node)
```bash
cd concepts/workloads/pods/user-namespaces
kubectl apply -f 00-userns-pods.yaml ; sleep 12
for p in with-userns without-userns; do
  echo "== $p: $(kubectl exec $p -n userns-demo -- id)   uid_map: $(kubectl exec $p -n userns-demo -- cat /proc/self/uid_map)"; done
```
Expected on a supporting node:
```
== with-userns:    uid=0(root) ...   uid_map: 0  <e.g. 1048576>  65536    <- container root = host UID 1048576
== without-userns: uid=0(root) ...   uid_map: 0  0  4294967295            <- identity mapping: root IS host root
```
Check from the node: `ps -eo user,pid,args | grep 'sleep infinity'` shows **two different users**.
**On minikube (docker driver):**
```bash
kubectl get pods -n userns-demo
#   with-userns      0/1  ContainerCreating     <- stuck
#   without-userns   1/1  Running
kubectl get events -n userns-demo --field-selector involvedObject.name=with-userns,type=Warning -o jsonpath='{.items[-1:].message}'
#   ... runc create failed: ... error mounting "sysfs" to rootfs at "/sys": ... operation not permitted
minikube ssh -- "ps -eo user:12,pid,args | grep '[s]leep infinity'"     # root ... sleep infinity  (the non-userns pod: real root)
```

## Lab 2 – Capabilities lose their power (needs a VM-based node)
On a supporting node, add `securityContext.capabilities.add: ["SYS_ADMIN"]` to `with-userns` and try `mount -t tmpfs none /mnt` (works: namespace-local), then `cat /proc/1/root/etc/shadow` from the node's perspective (denied).

## Lab 3 – Host namespaces are not allowed with it
```bash
kubectl apply -f 01-userns-with-hostnetwork.yaml
#   The Pod "userns-hostnet" is invalid: spec.hostNetwork: Forbidden: when `hostUsers` is false
```

## Lab 4 – Pod Security Standards are relaxed for userns pods
```bash
kubectl apply -f 02-restricted-namespace.yaml
#   pod/root-in-userns created                 <- runs as root, yet admitted under "restricted"
sed 's/  hostUsers: false/  hostUsers: true/; s/root-in-userns/root-no-userns/' 02-restricted-namespace.yaml | kubectl apply -f -
#   Forbidden: violates PodSecurity "restricted:latest": runAsNonRoot != true ...
```
Same pod and same namespace, and only `hostUsers` decides. Root inside a user namespace is no threat to the host. (`root-in-userns` itself then hits the minikube limitation from Lab 1.)

---

## Useful commands
```bash
kubectl explain pod.spec.hostUsers
kubectl exec <pod> -- cat /proc/self/uid_map
kubectl get --raw /api/v1/nodes/<node>/proxy/metrics | grep user_namespaced
```

## Cleanup
```bash
./cleanup.sh
```
