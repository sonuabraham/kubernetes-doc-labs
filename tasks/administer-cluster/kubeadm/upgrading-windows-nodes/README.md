# Upgrading Windows nodes – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/upgrading-windows-nodes/

> ⚠️ This lab needs a Windows worker, and minikube can't run one. It runs what can be run for real from Linux against the `kubeadm-lab` cluster:
> - [fetch-and-verify.sh](fetch-and-verify.sh) downloads the page's three binaries (`kubeadm.exe`, `kubelet.exe`, `kube-proxy.exe`), checks their SHA-256 and identifies them.
> - [fake-win-node.sh](fake-win-node.sh) creates an API-only Windows Server 2022 Node, `win-node`. A heartbeat loop plays its kubelet and can "restart with a new kubelet.exe", so `drain`, `uncordon` and the VERSION column act on something real.
> - The sig-windows-tools **HostProcess kube-proxy** DaemonSet is upgraded by re-applying it with a newer image tag (the page's note).
>
> The PowerShell steps (`stop-service`, `curl.exe -Lo`, `restart-service`, `kubeadm upgrade node`) are shown with what they do.

## Key ideas (read first)

| Step | On Windows | Linux equivalent ([../upgrading-linux-nodes](../upgrading-linux-nodes/)) |
|---|---|---|
| Upgrade kubeadm | `curl.exe -Lo C:\k\kubeadm.exe https://dl.k8s.io/v1.37.0/bin/windows/amd64/kubeadm.exe`. There are no packages; you replace the binary. | apt/dnf `kubeadm=1.37.x` |
| Drain | `kubectl drain <node> --ignore-daemonsets`, from any machine with API access | same |
| kubelet config | `kubeadm upgrade node` (re-downloads `kubelet-config` into `config.yaml`) | same |
| kubelet | `stop-service kubelet` → replace `kubelet.exe` → `restart-service kubelet` (an nssm service, see [../adding-windows-nodes](../adding-windows-nodes/)) | apt + `systemctl restart kubelet` |
| kube-proxy | Windows **service**: stop → replace `kube-proxy.exe` → restart. **HostProcess DaemonSet**: apply the manifest with the new image tag. | kubeadm's kube-proxy DaemonSet, upgraded by `kubeadm upgrade apply` |
| Uncordon | `kubectl uncordon <node>` | same |

Why the order matters: Windows binaries are **replaced in place**, and a running `.exe` is locked on Windows. That's why the page stops the service before the download and restarts it after.

---

## Step 0
```bash
cd tasks/administer-cluster/kubeadm
# kubeadm-lab with a v1.37 control plane, e.g. left over from ../upgrading-linux-nodes
kubectl --context kubeadm-lab get nodes
cd upgrading-windows-nodes
K="kubectl --context kubeadm-lab"
```

## Lab 1 – The three downloads, verified
```bash
./fetch-and-verify.sh v1.37.0          # ~170 MB into dl/ (gitignored)
#   kubeadm.exe: OK
#      PE32+ executable for MS Windows 6.01 (console), 72 MB, embedded version: v1.37.0
#   kubelet.exe: OK
#      PE32+ executable for MS Windows 6.01 (console), 57 MB, embedded version: v1.37.0
#   kube-proxy.exe: OK
#      PE32+ executable for MS Windows 6.01 (console), 43 MB, embedded version: v1.37.0
```
On the Windows node, the page's `curl.exe -Lo <path-to-kubeadm.exe> "https://dl.k8s.io/v1.37.0/bin/windows/amd64/kubeadm.exe"` does the same download. Check it with `(Get-FileHash kubeadm.exe).Hash -eq (curl.exe -sL <url>.sha256)`.

## Lab 2 – Drain, "upgrade the kubelet", uncordon
```bash
./fake-win-node.sh up v1.36.0
$K get nodes
#   kubeadm-lab       Ready    control-plane   v1.37.0
#   kubeadm-lab-m03   Ready    <none>          v1.37.0
#   win-node          Ready    <none>          v1.36.0      <- the Windows worker to upgrade
$K drain win-node --ignore-daemonsets
#   node/win-node cordoned
#   Warning: ignoring DaemonSet-managed Pods: kube-system/kindnet-th2cq     <- minikube's Linux CNI targets Windows too (see ../adding-windows-nodes Lab 4)
#   node/win-node drained                                                     <- the docs' expected output
```
On the node you'd now run `kubeadm upgrade node`, then `stop-service kubelet; curl.exe -Lo C:\k\kubelet.exe ...; restart-service kubelet`. The heartbeat plays the restarted kubelet:
```bash
./fake-win-node.sh kubelet v1.37.0
$K get node win-node
#   win-node   Ready,SchedulingDisabled   <none>   v1.37.0     <- VERSION is .status.nodeInfo.kubeletVersion, reported by the kubelet
$K uncordon win-node
#   node/win-node uncordoned
```

## Lab 3 – kube-proxy as a HostProcess DaemonSet: upgrade = new manifest
The sig-windows-tools manifest has a `KUBE_PROXY_VERSION` placeholder in the image tag. It's a **HostProcess** Pod (`windowsOptions.hostProcess: true`, `runAsUserName: NT AUTHORITY\system`, `hostNetwork`), restricted to `kubernetes.io/os: windows`, and it reuses kubeadm's `kube-proxy` ServiceAccount and ConfigMap.
```bash
curl -sSLo dl/kube-proxy.yml https://raw.githubusercontent.com/kubernetes-sigs/sig-windows-tools/master/hostprocess/calico/kube-proxy/kube-proxy.yml
#   (PrepareNode.ps1 also prints a .../hostprocess/flannel/kube-proxy/kube-proxy.yml URL: that one is 404 now)
grep -nE "image:|hostProcess|runAsUserName|kubernetes.io/os|name: kube-proxy$" dl/kube-proxy.yml
#   20:          hostProcess: true
#   21:          runAsUserName: "NT AUTHORITY\\system"
#   24:      - image: sigwindowstools/kube-proxy:KUBE_PROXY_VERSION-calico-hostprocess
#   43:        kubernetes.io/os: windows
sed 's/KUBE_PROXY_VERSION/v1.36.0/' dl/kube-proxy.yml | $K apply -f -
$K -n kube-system get ds kube-proxy-windows -o wide
#   kube-proxy-windows   1   1   0   1   0   kubernetes.io/os=windows   ...   sigwindowstools/kube-proxy:v1.36.0-calico-hostprocess
```
Upgrade it:
```bash
sed 's/KUBE_PROXY_VERSION/v1.37.0/' dl/kube-proxy.yml | $K apply -f -
#   daemonset.apps/kube-proxy-windows configured
$K -n kube-system get po -l k8s-app=kube-proxy-windows -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image,DELETING:.metadata.deletionTimestamp
#   kube-proxy-windows-ldhmn   sigwindowstools/kube-proxy:v1.36.0-calico-hostprocess   2026-11-13T08:39:02Z   <- RollingUpdate deletes the old Pod first
```
A real kubelet would stop the old Pod and the DaemonSet would start the v1.37.0 one. The fake node has no kubelet to confirm termination, so remove the old Pod by hand:
```bash
$K -n kube-system delete po kube-proxy-windows-ldhmn --grace-period=0 --force       # use your Pod name
$K -n kube-system get po -l k8s-app=kube-proxy-windows -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image,NODE:.spec.nodeName
#   kube-proxy-windows-hc95f   sigwindowstools/kube-proxy:v1.37.0-calico-hostprocess   win-node
```
(These Pods stay `Pending` because nothing runs them, so `kubectl rollout status` never finishes here.)

---

## Useful commands
```powershell
# on the Windows node
stop-service kubelet ; curl.exe -Lo C:\k\kubelet.exe https://dl.k8s.io/v1.37.0/bin/windows/amd64/kubelet.exe ; restart-service kubelet
kubeadm upgrade node
C:\k\kubelet.exe --version ; Get-Service kubelet, kube-proxy, containerd
```
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,OS:.status.nodeInfo.operatingSystem,KUBELET:.status.nodeInfo.kubeletVersion
```

## Cleanup
```bash
./cleanup.sh     # deletes the kube-proxy-windows DaemonSet and win-node; Pods left bound to it are garbage-collected (~40 s)
```
