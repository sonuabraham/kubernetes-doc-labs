# Installing kubeadm – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

> The page installs kubeadm, kubelet and kubectl on Linux machines. Here a "machine" is a throwaway container made by
> [../machines.sh](../machines.sh) (NOT from the docs): kicbase image = Debian 12 + systemd + containerd 2.x, on its own Docker network,
> like a kind node but empty. [install-debian.sh](install-debian.sh) is the page's **Debian** tab verbatim
> (`{{< param "version" >}}` = `v1.37`). It fetches the real packages from pkgs.k8s.io.
>
> **Found:**
> - pkgs.k8s.io v1.37 installs **v1.37.2** (kubeadm, kubelet, kubectl) plus `kubernetes-cni`; ~77 MB, 26 s here.
> - **`SystemVerification` fails in a container unless the kernel config is readable:** `[ERROR SystemVerification]: failed to parse
>   kernel config: unable to load kernel module: "configs" … Module configs not found`. kubeadm looks for `/proc/config.gz` or
>   `/boot/config-$(uname -r)`. machines.sh mounts the host's `/boot` read-only. Then preflight passes. (The page mentions skipping this
>   check if you know your kernel is fine.)
> - **Swap:** the machines see the **host's** swap (`swapon --show` → `/swap.img 8G`; `/proc/swaps` isn't namespaced), so `sudo swapoff -a`
>   in a privileged container would switch off the host's swap. Don't. The page's other option, `failSwapOn: false`, is used in the
>   create-cluster lab. Preflight's warning is confusingly worded:
>   `[WARNING Swap]: swap is supported for cgroup v2 only. The kubelet must be properly configured to use swap …`, although the machine
>   *is* on cgroup v2.
> - **product_uuid isn't unique across these machines:** a container reads the host's `/sys/class/dmi/id/product_uuid`
>   (`008e3c35-…` on every machine). MAC addresses are unique. kubeadm doesn't check product_uuid; the page warns it "may fail" with
>   identical values. No problem showed up in the multi-machine labs here.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Prerequisites | Linux with glibc, 2 GB+ RAM, 2+ CPUs on control-plane machines, full connectivity, unique hostname/MAC/product_uuid, required ports open |
| Container runtime | must be installed first; kubeadm auto-detects containerd / CRI-O / cri-dockerd sockets |
| Packages | one repo **per minor version** (`pkgs.k8s.io/core:/stable:/v1.37/deb/`); `apt-mark hold` so upgrades are deliberate |
| Version skew | kubelet may be one minor version older than the API server, never newer |
| kubelet after install | crash-loops until `kubeadm init/join` writes `/var/lib/kubelet/config.yaml` |

## Lab
```bash
cd setup/production-environment/tools/kubeadm/install-kubeadm
minikube stop                                   # inotify on this host
../machines.sh up cp1                           # machine cp1: 172.30.0.2
../machines.sh x cp1 'uname -r; ip link show eth0 | grep ether; cat /sys/class/dmi/id/product_uuid; systemctl is-active containerd'
#   7.0.0-38-generic   link/ether b2:7b:…   008e3c35-48fd-4d59-9d00-684cbdff3231   active
../machines.sh x cp1 'nc 127.0.0.1 6443 -zv -w 2'        # Connection refused  (nothing listens yet – the page's port check)

../machines.sh x cp1 "$(cat install-debian.sh)"           # the docs' Debian steps
#   The following NEW packages will be installed: kubeadm kubectl kubelet kubernetes-cni
#   kubelet set on hold. kubeadm set on hold. kubectl set on hold.
../machines.sh x cp1 'kubeadm version -o short; kubelet --version; apt-mark showhold'
#   v1.37.2   Kubernetes v1.37.2   kubeadm kubectl kubelet
../machines.sh x cp1 'systemctl is-active kubelet; journalctl -u kubelet | grep -m1 "failed to load kubelet config"'
#   activating   … failed to load kubelet config file, path: /var/lib/kubelet/config.yaml   <- the expected crash loop
../machines.sh x cp1 'systemctl cat kubelet'
#   /lib/systemd/system/kubelet.service + /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf (the kubeadm drop-in)
```
NOT from the docs – let kubeadm check the prerequisites:
```bash
../machines.sh x cp1 'kubeadm init phase preflight'
#   without /boot:  [ERROR SystemVerification]: failed to parse kernel config …
#   with /boot (machines.sh default): only [WARNING Swap] …, then it pre-pulls the control-plane images
```

## Cleanup
The machine is reused by [../create-cluster-kubeadm](../create-cluster-kubeadm/). To remove all lab machines: `../machines.sh down`
(then `minikube start`).
