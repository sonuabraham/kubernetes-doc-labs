# Running Kubernetes Node Components as a Non-root User – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/kubelet-in-userns/

> ⚠️ **What's run here and what isn't.** A rootless node needs host preparation that changes the system: rootless Docker/Podman (rootlesskit, slirp4netns), cgroup controller delegation, an AppArmor profile on Ubuntu, and lingering user sessions. None of that is done here. Starting a user-level `rootlesskit` from a downloaded binary was also refused by this session's permission policy. So the lab does three things:
> 1. [check-prereqs.sh](check-prereqs.sh) checks the page's prerequisites on your host, read-only.
> 2. The docs' configuration files are **verbatim** ([containerd-config-docs.toml](containerd-config-docs.toml), [crio-docs.conf](crio-docs.conf), [kubelet-config-docs.yaml](kubelet-config-docs.yaml)), and the containerd one is validated with the real containerd 2.3.
> 3. A user-namespace Pod ([userns-pod.yaml](userns-pod.yaml), not from the docs) shows the "Kubernetes inside Kubernetes" building block, and why it fails inside minikube's Docker node.
>
> The supported way for minikube is the rootless Docker/Podman driver: `minikube start --driver=docker --container-runtime=containerd` with a rootless `dockerd` (`dockerd-rootless-setuptool.sh install`, then `docker context use rootless`). See the minikube driver docs the page links to.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Rootless mode** | The kubelet, the CRI runtime, the OCI runtime and CNI all run as an **unprivileged user**, inside a user namespace where they appear to be root. A container breakout lands on an ordinary user, not root. |
| **Prerequisites** | cgroup v2 with controllers delegated to the user (systemd `Delegate=yes`), a systemd user session, sysctls, `/etc/subuid` + `/etc/subgid` ranges, and the `KubeletInUserNamespace` gate (beta in 1.37). |
| **Ready-made options** | kind / minikube on rootless Docker or Podman, Usernetes (multi-node, VXLAN; also Kubernetes-in-Kubernetes with `hostUsers: false` Pods), Sysbox (no cgroup v2 or gate needed), K3s rootless. |
| **The hard way** | Unshare a user namespace and a mount namespace, writable `/etc /run /var/lib/kubelet ...` *inside* it, a delegated cgroup tree, slirp4netns/VPNKit networking, and port forwarding for 10250/NodePorts. |
| **Runtime config** | containerd: `disable_apparmor`, `restrict_oom_score_adj`, `disable_hugetlb_controller`, `fuse-overlayfs`, `SystemdCgroup = false`. CRI-O: `_CRIO_ROOTLESS=1`, `cgroup_manager = "cgroupfs"`. kubelet: the gate + `cgroupDriver: cgroupfs`. |
| **What the gate does** | The kubelet ignores errors setting `vm.overcommit_memory`, `vm.panic_on_oom`, `kernel.panic`, `kernel.panic_on_oops`, `kernel.keys.root_maxkeys`, `kernel.keys.root_maxbytes` (not permitted in a user namespace), and treats some `/dev/kmsg`/OOM-score failures as non-fatal. |

---

## Lab 1 – Is this host ready? (read-only)
```bash
cd tasks/administer-cluster/kubelet-in-userns
./check-prereqs.sh
#   cgroup v2:            cgroup2fs                         ✔
#   delegated controllers: cpu memory pids                  ✘ cpuset and io are not delegated to the user
#   subuid:               sonu:100000:65536                 ✔
#   subgid:               sonu:100000:65536                 ✔
#   newuidmap / newgidmap: /usr/bin/...                     ✔
#   rootlesskit / dockerd-rootless-setuptool.sh / slirp4netns: not installed      ✘ (docker-ce-rootless-extras)
#   unprivileged userns:  1                                 ✔
#   apparmor userns restriction: 1                          ✘ Ubuntu 24.04+: rootlesskit needs an AppArmor profile
#   user session (linger): Linger=no                        (needed so the user's services survive logout)
```
The fixes, all needing root:
- Delegate controllers with a systemd drop-in (`/etc/systemd/system/user@.service.d/delegate.conf`: `Delegate=cpu cpuset io memory pids`).
- Install the rootless extras package.
- Add the AppArmor profile from Docker's rootless docs.
- Run `loginctl enable-linger <user>`.

## Lab 2 – The docs' runtime and kubelet configuration
```bash
cat kubelet-config-docs.yaml
#   featureGates: {KubeletInUserNamespace: true}
#   cgroupDriver: "cgroupfs"
kubectl get --raw /api/v1/nodes/minikube/proxy/metrics | grep kubernetes_feature_enabled | grep KubeletInUserNamespace
#   kubernetes_feature_enabled{name="KubeletInUserNamespace",stage="BETA"} 1        <- beta and on by default in 1.37
minikube cp containerd-config-docs.toml /tmp/userns-containerd.toml
minikube ssh -- 'sudo containerd --config /tmp/userns-containerd.toml config dump | grep -nE "^version|disable_apparmor|restrict_oom_score_adj|disable_hugetlb_controller|snapshotter = |SystemdCgroup|level="'
#   level=warning msg="Configuration migrated from version 2, use `containerd config migrate` to avoid migration"
#   version = 4
#   snapshotter = 'fuse-overlayfs'
#   disable_apparmor = true   restrict_oom_score_adj = true   disable_hugetlb_controller = true
#   SystemdCgroup = false
```
The docs' file is still accepted by containerd 2.x, but it's in the **old version-2 format**. Convert it with `containerd config migrate` (or write the version-3/4 layout) so it doesn't depend on the automatic migration.

The docs' kube-proxy config ([kube-proxy-config-docs.yaml](kube-proxy-config-docs.yaml): `conntrack` values of 0 skip the `nf_conntrack_*` sysctls a user namespace can't set), validated by the real v1.37 binary:
```bash
docker run --rm --entrypoint kube-proxy -v $PWD/kube-proxy-config-docs.yaml:/c.yaml:ro registry.k8s.io/kube-proxy:v1.37.0 --config=/c.yaml --cleanup
#   (no error - mode "iptables" is valid)
# with the alternative from its comment, mode: "userspace":
#   "command failed" err="failed validate: KubeProxyConfiguration.Mode.ProxyMode: Invalid value: \"userspace\": must be iptables, ipvs, nftables or blank ..."
```
The userspace proxy mode was removed in v1.26, so the comment `# or "userspace"` is out of date.

**Caveats (from the page):** most non-local volume drivers (`nfs`, `iscsi`) don't work, while `local`, `hostPath`, `emptyDir`, `configMap`, `secret` and `downwardAPI` do. Some CNI plugins don't work; Flannel (VXLAN) is known to work.

## Lab 3 – User-namespace Pods (the Kubernetes-in-Kubernetes building block)
```bash
kubectl apply -f userns-pod.yaml                    # userns-demo (hostUsers: false) + hostusers-demo (default)
kubectl logs hostusers-demo
#   uid=0(root) gid=0(root) ...   uid_map: 0 0 4294967295         <- root in the container IS root on the node
kubectl get po userns-demo                          # ContainerCreating, forever
kubectl get events --field-selector involvedObject.name=userns-demo,reason=FailedCreatePodSandBox -o jsonpath='{.items[-1:].message}'
#   ... runc create failed: unable to start container process: error during container init:
#   error mounting "sysfs" to rootfs at "/sys": ... operation not permitted
kubectl delete -f userns-pod.yaml
```
`UserNamespacesSupport` is GA, but minikube's node is itself a container (kic), and a nested user namespace can't mount `sysfs` there. On a real Linux node (kernel ≥ 6.3, containerd 2 / CRI-O 1.25+, idmap-capable filesystem) the Pod starts, and `uid_map` shows `0 <high-host-uid> 65536`. Usernetes uses such Pods as the nodes of an inner cluster. This kind of nesting limit is also why the page points to rootless engines and Sysbox.

---

## Useful commands
```bash
cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers
grep "^$USER:" /etc/subuid /etc/subgid
unshare -U -r id                      # quick test: can I create a user namespace?
containerd config migrate             # convert an old config to the current version
```

## Cleanup
```bash
kubectl delete -f userns-pod.yaml --ignore-not-found
minikube ssh -- 'sudo rm -f /tmp/userns-containerd.toml'
```
