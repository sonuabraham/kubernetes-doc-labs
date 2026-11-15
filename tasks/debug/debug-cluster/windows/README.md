# Windows debugging tips – Lab notes

Based on: https://kubernetes.io/docs/tasks/debug/debug-cluster/windows/

> A list of tips for Windows *nodes* (HNS networking, Flannel on Windows, `start.ps1`, PowerShell). None of that can run on minikube.
> The one tip with a Linux-side, reproducible part is **"ErrImgPull / ImagePullBackOff → make sure the Pod lands on a compatible Windows node"**,
> shown in [wrong-os.yaml](wrong-os.yaml) (not from the docs). Everything else is summarised as a checklist.
> Related labs: [concepts/windows](../../../../concepts/windows/) (fake Windows nodes, scheduling), [adding-windows-nodes](../../../administer-cluster/kubeadm/adding-windows-nodes/).
>
> ⚠️ Lab 1 makes the Linux node download several GB of Windows image layers before it fails. Run it once and delete the Pod promptly.

## Lab 1 – A Windows image on a Linux node (not from the docs)
```bash
cd tasks/debug/debug-cluster/windows
kubectl apply -f wrong-os.yaml
kubectl get pods -o wide
#   no-selector     ContainerCreating   minikube     <- no OS constraint: the scheduler happily picks the Linux node
#   with-selector   Pending             <none>       <- nodeSelector kubernetes.io/os: windows (+ spec.os.name: windows)
kubectl describe pod with-selector | grep FailedScheduling
#   0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector. …
kubectl describe pod no-selector | tail -2
#   Normal  Pulling  3m41s  kubelet  Pulling image "mcr.microsoft.com/windows/servercore/iis:windowsservercore-ltsc2022"   <- for minutes
minikube ssh -- sudo crictl pull mcr.microsoft.com/windows/servercore/iis:windowsservercore-ltsc2022
#   … failed to pull and unpack image …: failed to extract layer (application/vnd.docker.image.rootfs.diff.tar.gzip sha256:…) …
kubectl delete -f wrong-os.yaml --now
```
What happened: containerd on the Linux node found no `linux/amd64` entry in the image and still **downloaded the Windows layers**
(multi-GB), then failed to unpack them. The Pod sat in `ContainerCreating`/`Pulling` for minutes before any `ErrImagePull`.
Partial downloads stayed behind (`/var/lib/containerd/io.containerd.content.v1.content/ingest` grew by 1.4 GB). containerd
garbage-collects stale ingests later.
The fix, as the page says: schedule Windows Pods only on Windows nodes, with `nodeSelector: kubernetes.io/os: windows` (and
`node.kubernetes.io/windows-build` for the OS version), taints on Windows nodes, or a RuntimeClass with a scheduling section.

## Checklist from the page (Windows node side)
| Symptom | Check |
|---|---|
| Pods stuck in `ContainerCreating` or restarting | pause image matches the Windows build (containerd: `sandbox_image` in `config.toml`) |
| `ErrImgPull` / `ImagePullBackOff` | Pod on a *compatible* Windows node (OS build). See Lab 1 for the Linux-node version. |
| no network in Pods (VMs) | MAC spoofing enabled on the VM NICs |
| can't `ping` outside | Windows Pods have no ICMP egress: test with `curl`. Check the `ExceptionList` in `cni.conf` (cluster, service and management subnets) so outside traffic is SNAT'ed. |
| node can't reach its own `NodePort` | known limitation: use another node or an external client |
| node can't reach Service IPs | known limitation (Pods can) |
| vNICs / HNS endpoints disappear | run kube-proxy with `--hostname-override=$(hostname)` |
| "no network adapter" at kubelet start | `Get-HnsNetwork \| ? Name -ieq "cbr0"`, `Get-NetAdapter \| ? Name -Like "vEthernet (Ethernet*"`; fix `InterfaceName` in `start.ps1` |
| DNS issues | Windows DNS limitations (no `ndots`-style search behaviour) |
| `kubectl port-forward`: "wincat not found" | pause image with `wincat.exe` (`mcr.microsoft.com/oss/kubernetes/pause:3.6`+) |
| install fails behind a proxy | set machine-wide `HTTP_PROXY` / `HTTPS_PROXY` |
| Flannel: node re-joins badly | delete `C:\k\SourceVip.json`, `C:\k\SourceVipRequest.json` |
| Flannel: "Waiting for the Network to be created" | restart `start.ps1` / `flanneld.exe` manually |
| missing `/run/flannel/subnet.env` | copy it from a Linux node to `C:\run\flannel\subnet.env` and change `FLANNEL_SUBNET` |

## Cleanup
```bash
./cleanup.sh
```
