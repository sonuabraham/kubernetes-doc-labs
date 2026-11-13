# Upgrading Linux nodes – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/upgrading-linux-nodes/

> Real worker upgrade, **v1.36.0 → v1.37.0**, on the throwaway profile **`kubeadm-lab`**, run as a control plane plus one worker (`minikube node add`). The page assumes the control plane is already upgraded. [../upgrade-control-plane.sh](../upgrade-control-plane.sh) does that first; it's the [../kubeadm-upgrade](../kubeadm-upgrade/) lab condensed. On the worker, [../pkg-upgrade.sh](../pkg-upgrade.sh) runs the docs' apt commands (`repo`, `kubeadm`, `kubelet` steps), and [../node.sh](../node.sh) with `N=<worker>` runs node commands as root.
>
> **minikube adjustments** (the same as in the kubeadm-upgrade lab):
> 1. Put minikube's old kubelet on `PATH` for kubeadm's preflight.
> 2. `--ignore-preflight-errors=SystemVerification`, because the node is a container.
> 3. Point minikube's kubelet drop-in at the package's `/usr/bin/kubelet`.
>
> **inotify:** two kic nodes need room, so `minikube stop` the default cluster first (see [../adding-linux-nodes](../adding-linux-nodes/)).

## Key ideas (read first)

| Step (on each worker, one at a time) | Why |
|---|---|
| **Package repo** for the new minor | pkgs.k8s.io has one repo per minor ([../change-package-repository](../change-package-repository/)). |
| **kubeadm + kubectl** first | kubeadm must be the target version to run the upgrade. kubectl on the node must stay within ±1 minor of the API server. |
| **`kubeadm upgrade node`** | On a worker this **only refreshes `/var/lib/kubelet/config.yaml`** from the `kubelet-config` ConfigMap. It skips the control-plane, kubeconfig and addon phases. |
| **Drain** (from a control-plane node / your laptop) | `kubectl drain <node> --ignore-daemonsets` cordons the node and **evicts** Pods (PDBs respected). DaemonSet Pods stay. Bare Pods need `--force` and are **lost**. |
| **kubelet** + `daemon-reload` + `restart` | The node only reports the new version once the new kubelet binary runs. |
| **Uncordon** | Makes the node schedulable again. Evicted Pods **don't** move back by themselves. |
| **Skew** | The kubelet may be up to 3 minors **older** than the API server, never newer. That's why workers go after the control plane. |

---

## Step 0 – control plane at 1.37, worker at 1.36
```bash
cd tasks/administer-cluster/kubeadm
minikube stop                                   # default cluster: free inotify instances
minikube delete -p kubeadm-lab; ./start-kubeadm-lab.sh v1.36.0
minikube node add -p kubeadm-lab                # worker kubeadm-lab-m02 (or -m03 ...), v1.36.0
./upgrade-control-plane.sh 1.37.0
#      kubeadm | 1.37.2-1.1 | https://pkgs.k8s.io/core:/stable:/v1.37/deb  Packages
#   v1.37.0
#   [upgrade] SUCCESS! A control plane node of your cluster was upgraded to "v1.37.0".
#   Kubernetes v1.37.0
#   NAME              STATUS   ROLES           VERSION
#   kubeadm-lab       Ready    control-plane   v1.37.0
#   kubeadm-lab-m03   Ready    <none>          v1.36.0       <- the node this lab upgrades
cd upgrading-linux-nodes
W=$(kubectl --context kubeadm-lab get nodes -o name | grep -- -m0 | cut -d/ -f2); echo $W
minikube -p kubeadm-lab cp ../pkg-upgrade.sh $W:/tmp/pkg-upgrade.sh
K="kubectl --context kubeadm-lab"
$K create ns upgrade-demo && $K -n upgrade-demo create deploy web --image=nginx --replicas=3 && $K -n upgrade-demo rollout status deploy web
$K -n upgrade-demo get po -o wide
#   web-...-4f76c   Running   kubeadm-lab
#   web-...-d692p   Running   kubeadm-lab-m03
#   web-...-wccrp   Running   kubeadm-lab-m03
```

## Lab 1 – Package repo, then kubeadm and kubectl (on the worker)
```bash
N=$W ../node.sh 'which kubeadm kubelet kubectl; ls /var/lib/minikube/binaries; apt-mark showhold'
#   v1.36.0           <- nothing on PATH, nothing held: minikube only copied binaries in
N=$W ../node.sh 'bash /tmp/pkg-upgrade.sh repo 1.37.0 && bash /tmp/pkg-upgrade.sh kubeadm 1.37.0'
#      kubeadm | 1.37.2-1.1 | https://pkgs.k8s.io/core:/stable:/v1.37/deb  Packages
#   kubeadm set on hold.
#   kubectl set on hold.
#   v1.37.0
```
That's the docs' `apt-mark unhold kubeadm kubectl && apt-get update && apt-get install -y kubeadm='1.37.x-*' kubectl='1.37.x-*' && apt-mark hold kubeadm kubectl`. This lab pins `1.37.0-1.1` to match the control plane.

## Lab 2 – `kubeadm upgrade node`
```bash
N=$W ../node.sh 'unset KUBECONFIG; kubeadm upgrade node'
#   [ERROR SystemVerification]: couldn't get kubelet version: cannot execute 'kubelet --version': executable file not found in $PATH
N=$W ../node.sh 'unset KUBECONFIG; cp /var/lib/kubelet/config.yaml /root/config.before.yaml
  PATH=/var/lib/minikube/binaries/v1.36.0:$PATH kubeadm upgrade node --ignore-preflight-errors=SystemVerification
  diff /root/config.before.yaml /var/lib/kubelet/config.yaml && echo "config.yaml unchanged"'
#   [upgrade] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
#   [upgrade/preflight] Skipping prepull. Not a control plane node.
#   [upgrade/control-plane] Skipping phase. Not a control plane node.
#   [upgrade/kubeconfig] Skipping phase. Not a control plane node.
#   [upgrade] Backing up kubelet config file to /etc/kubernetes/tmp/kubeadm-kubelet-config-<date>/config.yaml
#   [kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
#   [upgrade/kubelet-config] The kubelet configuration for this node was successfully upgraded!
#   [upgrade/addon] Skipping the addon/coredns phase. Not a control plane node.
#   [upgrade/addon] Skipping the addon/kube-proxy phase. Not a control plane node.
#   config.yaml unchanged        <- nothing changed in KubeletConfiguration between 1.36 and 1.37 here
```
(`unset KUBECONFIG`: `node.sh` points it at `admin.conf`, which only control-plane nodes have. A worker uses `/etc/kubernetes/kubelet.conf`.)

## Lab 3 – Drain (from the control plane / your machine)
```bash
$K drain $W --ignore-daemonsets
#   node/kubeadm-lab-m03 cordoned
#   error: unable to drain node "kubeadm-lab-m03" ... cannot delete Pods that declare no controller (use --force to override): kube-system/storage-provisioner
$K get nodes        # kubeadm-lab-m03   Ready,SchedulingDisabled   v1.36.0    <- cordoned, but the Pods are still there
```
minikube's `storage-provisioner` is a **bare Pod**. Nothing recreates it after eviction, so drain refuses. `--force` deletes it anyway. (In this cluster that means losing dynamic PV provisioning, which is fine for a throwaway profile.)
```bash
$K drain $W --ignore-daemonsets --force
#   Warning: ignoring DaemonSet-managed Pods: kube-system/kindnet-hfb99, kube-system/kube-proxy-n5qzh;
#            deleting Pods that declare no controller: kube-system/storage-provisioner
#   evicting pod upgrade-demo/web-...-wccrp
#   evicting pod upgrade-demo/web-...-d692p
#   evicting pod kube-system/storage-provisioner
#   node/kubeadm-lab-m03 drained
$K -n upgrade-demo get po -o wide
#   web-...-4f76c   Running             kubeadm-lab
#   web-...-jltcv   ContainerCreating   kubeadm-lab      <- replacements on the remaining node
#   web-...-lt9mj   ContainerCreating   kubeadm-lab
```

## Lab 4 – Upgrade the kubelet, restart, uncordon
```bash
N=$W ../node.sh 'bash /tmp/pkg-upgrade.sh kubelet 1.37.0; systemctl cat kubelet | grep -E "^# /|^ExecStart=/" | cut -c1-90'
#   kubelet set on hold.
#   Kubernetes v1.37.0
#   # /lib/systemd/system/kubelet.service                      ExecStart=/usr/bin/kubelet
#   # /etc/systemd/system/kubelet.service.d/10-kubeadm.conf    ExecStart=/usr/bin/kubelet --bootstrap-kubeconfig=...   <- sed'ed from minikube's binary
```
(That's the docs' `apt-mark unhold kubelet && apt-get install -y kubelet='1.37.x-*' && apt-mark hold kubelet`, then `systemctl daemon-reload && systemctl restart kubelet`.)
```bash
$K get nodes
#   kubeadm-lab       Ready                      control-plane   v1.37.0
#   kubeadm-lab-m03   Ready,SchedulingDisabled   <none>          v1.37.0     <- new kubelet reported
$K uncordon $W
$K get nodes
#   kubeadm-lab-m03   Ready    <none>   v1.37.0
$K -n upgrade-demo get po -o wide       # all 3 still on kubeadm-lab: uncordon doesn't rebalance
$K -n upgrade-demo rollout restart deploy web && $K -n upgrade-demo rollout status deploy web     # spreads them again
```

---

## Useful commands
```bash
apt-mark showhold ; apt-cache madison kubeadm
kubeadm upgrade node                         # on the node being upgraded
kubectl drain <node> --ignore-daemonsets [--force] [--delete-emptydir-data]
kubectl uncordon <node>
kubectl get nodes -o custom-columns=NAME:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion,SCHED:.spec.unschedulable
```

## Cleanup
```bash
$K delete ns upgrade-demo
minikube stop -p kubeadm-lab ; kubectl config use-context minikube ; minikube start     # restore the default cluster
```
The next lab ([../upgrading-windows-nodes](../upgrading-windows-nodes/)) can reuse this profile.
