# Running Kubelet in Standalone Mode – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/cluster-management/kubelet-standalone/

> The page needs **root on a Linux machine with systemd**, and it installs CRI-O, CNI plugins and a kubelet into system directories.
> This lab does **not** touch the host. The "machine" is a throwaway privileged container from minikube's own **kicbase** image (Debian 12
> + systemd + CRI-O 1.35.7 + crun/runc/conmon + CNI plugins v1.9.1), and the kubelet **v1.37.0** binary is copied out of the minikube
> node. Nothing is downloaded. [standalone-machine.sh](standalone-machine.sh) (NOT from the docs) creates and deletes it.
> [docs-steps.sh](docs-steps.sh) holds the docs' commands, run inside it; every deviation there is marked `LAB:`.
>
> **Found:**
> - **⚠ The page's "Container Runtime" cleanup deletes whole system directories:** `sudo rm -rf /usr/local/bin`, `/usr/local/lib`,
>   `/usr/local/share`. That removes everything anyone installed there, not just CRI-O. (In kicbase, `/usr/local/bin` holds buildkit,
>   nerdctl, crictl, the entrypoint…) Don't run it as written on a real machine; remove only the files the installer created.
> - **`swapon --show` inside a container shows the host's swap** (`/swap.img 8G`). `/proc/swaps` isn't namespaced, and in a privileged
>   container `swapoff -a` would really turn off the host's swap. So this lab uses the page's alternative, `failSwapOn: false`, appended
>   to `kubelet.yaml`.
> - **CRI-O can't start when `/var` is on overlayfs:** `'overlay' is not supported over overlayfs, a mount_program is required`.
>   That only matters for container-based "machines" (kind and minikube put `/var` on a volume for the same reason). standalone-machine.sh
>   mounts a Docker volume at `/var`.
> - `jq` isn't installed in kicbase. `python3 -m json.tool` / a python one-liner replace `jq '.'` and `jq '.items[].status.podIP'`.
> - `/healthz?verbose` lists one more check than the page shows: `[+]device-plugin ok`.
> - The docs' `kubelet.service` heredoc keeps the `\` line continuation unquoted, so the shell joins it: the file says
>   `ExecStart=/usr/bin/kubelet  --config=/etc/kubernetes/kubelet.yaml`. That's harmless.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Standalone mode | kubelet **without** `--kubeconfig` → no API server, no Node object, no scheduler |
| Static Pods | the kubelet runs every manifest in `staticPodPath` (`/etc/kubernetes/manifests`); delete the file → Pod stops |
| CRI | the kubelet talks to CRI-O over `unix:///var/run/crio/crio.sock` |
| CNI | CRI-O calls the `bridge` plugin: bridge `cni0` 10.85.0.1/16, one veth pair per Pod, IPs from `host-local` |
| `readOnlyPort: 10255` | unauthenticated HTTP API (`/healthz`, `/pods`): tutorial only, never in production |
| No ConfigMaps/Secrets | there is no API server to get them from |

## Lab
```bash
cd tutorials/cluster-management/kubelet-standalone
./standalone-machine.sh up              # container "kubelet-standalone" (systemd running), /root/kubelet = v1.37.0
minikube stop                           # optional: frees inotify instances (the kubelet was already copied)
docker cp docs-steps.sh kubelet-standalone:/root/
X="docker exec -w /root kubelet-standalone bash docs-steps.sh"
```

### Prepare the system
```bash
$X prepare
#   NAME      TYPE SIZE USED   PRIO
#   /swap.img file   8G 284.2M   -1      <- the HOST's swap → failSwapOn: false, no swapoff
#   1                                    <- ip_forward already on
```

### CRI-O and CNI
```bash
$X crio
#   (docs: curl https://raw.githubusercontent.com/cri-o/packaging/main/get > crio-install; sudo bash crio-install – not needed, kicbase has it)
#   writes /etc/cni/net.d/11-crio-ipv4-bridge.conflist (verbatim from the page)
#   systemctl enable --now crio.service   → active
#   /opt/cni/bin/bridge --version         → CNI bridge plugin v1.9.1 (protocols up to 1.1.0)
```

### kubelet
```bash
$X kubelet
#   /etc/kubernetes/kubelet.yaml = the docs' file + failSwapOn: false
#   /usr/bin/kubelet, /etc/systemd/system/kubelet.service, enable --now → active
#   curl http://localhost:10255/healthz?verbose
#     [+]ping ok  [+]log ok  [+]syncloop ok  [+]device-plugin ok  healthz check passed
#   curl http://localhost:10255/pods
#     {"kind":"PodList","apiVersion":"v1","metadata":{},"items":null}
```

### Run a Pod
```bash
$X pod                                  # static-web.yaml → /etc/kubernetes/manifests/
$X info
#   "10.85.0.2"
#   <!DOCTYPE html> <html> <head> <title>Welcome to nginx!</title>
```
NOT from the docs – a closer look (inside the machine: `./standalone-machine.sh sh`):
```bash
curl -s http://localhost:10255/pods | python3 -m json.tool | less
#   name static-web-kubelet-standalone (node name appended), phase Running,
#   annotations kubernetes.io/config.source: file, config.hash …
ip -br addr show cni0                   # cni0  UP  10.85.0.1/16
ip -br link | grep veth                 # vethed4c9b7e@if3  UP   <- host end of the Pod's veth pair
crictl --runtime-endpoint unix:///var/run/crio/crio.sock pods    # static-web-kubelet-standalone  Ready
crictl --runtime-endpoint unix:///var/run/crio/crio.sock ps      # web  Running
ls /var/log/pods /var/log/containers /var/lib/cni/networks/crio  # Pod log dir, container log symlink, the IP lease 10.85.0.2
rm /etc/kubernetes/manifests/static-web.yaml                      # /pods → "items":null within 2 s; the container stops
```

## Cleanup
The docs remove the kubelet, CRI-O and CNI files one by one (see the warning above). Here the whole machine is a container:
```bash
./cleanup.sh            # = ./standalone-machine.sh down: docker rm -f kubelet-standalone; docker volume rm kubelet-standalone-var
minikube start          # if you stopped it
```
