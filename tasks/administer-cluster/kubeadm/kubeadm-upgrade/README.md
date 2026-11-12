# Upgrading kubeadm clusters – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/

> Real upgrade, **v1.36.0 → v1.37.0**, on the throwaway profile **`kubeadm-lab`** ([../start-kubeadm-lab.sh](../start-kubeadm-lab.sh)), following the docs' order: package repo → kubeadm → `upgrade plan` → `upgrade apply` → drain → kubelet + kubectl → restart → uncordon. Packages come from the real **pkgs.k8s.io** apt repo, installed into the minikube node (Debian 12). [../node.sh](../node.sh) runs the node commands as root.
>
> Three minikube-specific adjustments are needed, and each one says something about how kubeadm works:
> 1. minikube's kubelet isn't on `PATH`.
> 2. The node is a container, so the kernel config check fails.
> 3. minikube's kubelet drop-in hard-codes its own binary path.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **One minor at a time** | 1.36 → 1.37, never skipping a minor. Patch upgrades within a minor work the same way. |
| **Order** | First control-plane node: `kubeadm upgrade apply`. Other control-plane nodes: `kubeadm upgrade node`. Then the kubelet on each node (drain → upgrade → uncordon). Workers: `../upgrading-linux-nodes`. |
| **Package repo per minor** | pkgs.k8s.io has one repo **per minor version**. Point it at the new minor first (`../change-package-repository`). Packages are **held** (`apt-mark hold`) so routine updates don't upgrade Kubernetes by accident. |
| **upgrade plan** | Shows what can be upgraded: the latest patch of the current minor **and** the latest stable, plus component-config versions. |
| **upgrade apply** | Preflight → pull images → upgrade **etcd, apiserver, controller-manager, scheduler** static Pods one by one (with backups) → kubelet config → addons (CoreDNS, kube-proxy). **Renews certificates** too. |
| **kubelet is manual** | `apply` doesn't replace the kubelet binary. The node keeps reporting the old version until you do. |
| **Drain** | `kubectl drain <node> --ignore-daemonsets` before the kubelet restart. Bare Pods (no controller) block it unless `--force`, and then they're **gone**. |
| **Recovery** | Manifests and etcd are backed up under `/etc/kubernetes/tmp/`. `apply` is idempotent, so re-run it after a failure. |

---

## Step 0
```bash
cd tasks/administer-cluster/kubeadm
./start-kubeadm-lab.sh v1.36.0
kubectl --context kubeadm-lab get nodes          # kubeadm-lab   Ready   control-plane   v1.36.0
```

## Lab 1 – Package repo for the target minor, and kubeadm
(The repo steps themselves are explained in `../change-package-repository`.)
```bash
./node.sh 'curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
  apt-get update >/dev/null; apt-cache madison kubeadm | head -3'
#   kubeadm | 1.37.2-1.1 | https://pkgs.k8s.io/core:/stable:/v1.37/deb  Packages
#   kubeadm | 1.37.1-1.1 | ...
#   kubeadm | 1.37.0-1.1 | ...
./node.sh 'apt-mark unhold kubeadm; apt-get install -y kubeadm=1.37.0-1.1 >/dev/null && apt-mark hold kubeadm; kubeadm version -o short'
#   v1.37.0
```

## Lab 2 – `kubeadm upgrade plan`
```bash
./node.sh 'kubeadm upgrade plan'
#   COMPONENT   NODE          CURRENT   TARGET
#   kubelet     kubeadm-lab   v1.36.0   v1.37.2                  <- "must be upgraded manually"
#   kube-apiserver            kubeadm-lab   v1.36.0   v1.37.2
#   kube-controller-manager   kubeadm-lab   v1.36.0   v1.37.2
#   kube-scheduler            kubeadm-lab   v1.36.0   v1.37.2
#   kube-proxy                              1.36.0    v1.37.2
#   CoreDNS                                 v1.14.2   v1.14.6
#   etcd                      kubeadm-lab   3.6.8-0   3.7.0-0
#   You can now apply the upgrade by executing the following command:   kubeadm upgrade apply v1.37.2
#   Note: Before you can perform this upgrade, you have to update kubeadm to v1.37.2.
#   (a second table offers the latest 1.36 patch: kubeadm upgrade apply v1.36.6)
#   API GROUP                 CURRENT VERSION   PREFERRED VERSION   MANUAL UPGRADE REQUIRED
#   kubeproxy.config.k8s.io   v1alpha1          v1alpha1            no
#   kubelet.config.k8s.io     v1beta1           v1beta1             no
```

## Lab 3 – `kubeadm upgrade apply`
```bash
./node.sh 'kubeadm upgrade apply v1.37.0 -y'
#   [ERROR SystemVerification]: couldn't get kubelet version: cannot execute 'kubelet --version': executable file not found in $PATH
./node.sh 'PATH=/var/lib/minikube/binaries/v1.36.0:$PATH kubeadm upgrade apply v1.37.0 -y'
#   [ERROR SystemVerification]: failed to parse kernel config: unable to load kernel module: "configs" ...   <- node is a container
./node.sh 'PATH=/var/lib/minikube/binaries/v1.36.0:$PATH kubeadm upgrade apply v1.37.0 -y --ignore-preflight-errors=SystemVerification'
#   [upgrade/versions] Cluster version: v1.36.0   kubeadm version: v1.37.0
#   [upgrade/preflight] Pulling images required for setting up a Kubernetes cluster
#   [upgrade/staticpods] Preparing for "etcd" upgrade
#   [upgrade/staticpods] Renewing etcd-server certificate ... etcd-peer ... etcd-healthcheck-client
#   [upgrade/staticpods] Moving new manifest to "/etc/kubernetes/manifests/etcd.yaml" and backing up old manifest to "/etc/kubernetes/tmp/kubeadm-backup-manifests-..."
#   [upgrade/staticpods] Component "etcd" upgraded successfully!
#   [upgrade/staticpods] Preparing for "kube-apiserver" upgrade  (renews apiserver, apiserver-kubelet-client, front-proxy-client, apiserver-etcd-client)
#   ... kube-controller-manager, kube-scheduler
#   [upgrade] Backing up kubelet config file to /etc/kubernetes/tmp/kubeadm-kubelet-config-.../config.yaml
#   [upgrade] SUCCESS! A control plane node of your cluster was upgraded to "v1.37.0".          (3m18s, mostly image pulls)
kubectl --context kubeadm-lab get pods -n kube-system -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
#   coredns   registry.k8s.io/coredns/coredns:v1.14.6     etcd   registry.k8s.io/etcd:3.7.0-0
#   kube-apiserver / controller-manager / scheduler / kube-proxy   :v1.37.0
kubectl --context kubeadm-lab get nodes           # VERSION still v1.36.0   <- that column is the KUBELET
./node.sh 'ls /etc/kubernetes/tmp/'
#   kubeadm-backup-etcd-2026-11-12-10-09-04  kubeadm-backup-manifests-2026-11-12-10-09-04  kubeadm-kubelet-config-2026-11-12-10-11-34
./node.sh 'kubeadm certs check-expiration --cert-dir $PKI | sed -n 3,4p'
#   apiserver   Nov 12, 2027 10:08 UTC   364d        <- renewed by the upgrade
```

## Lab 4 – Drain, kubelet + kubectl, uncordon
```bash
kubectl --context kubeadm-lab drain kubeadm-lab --ignore-daemonsets
#   cannot delete Pods that declare no controller (use --force to override): kube-system/storage-provisioner
kubectl --context kubeadm-lab drain kubeadm-lab --ignore-daemonsets --force
#   pod/storage-provisioner evicted   pod/coredns-... evicted   node/kubeadm-lab drained
#   (single node: CoreDNS goes Pending until uncordon; the bare storage-provisioner Pod is gone for good)
./node.sh 'apt-mark unhold kubelet kubectl; apt-get install -y kubelet=1.37.0-1.1 kubectl=1.37.0-1.1 >/dev/null; apt-mark hold kubelet kubectl; systemctl cat kubelet | grep -E "^# /|^ExecStart=/"'
#   # /lib/systemd/system/kubelet.service                       ExecStart=/usr/bin/kubelet        <- from the package
#   # /etc/systemd/system/kubelet.service.d/10-kubeadm.conf     ExecStart=/var/lib/minikube/binaries/v1.36.0/kubelet ...   <- minikube's drop-in wins
./node.sh 'sed -i "s|ExecStart=/var/lib/minikube/binaries/v1.36.0/kubelet|ExecStart=/usr/bin/kubelet|" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
  systemctl daemon-reload && systemctl restart kubelet'          # the docs' two commands
kubectl --context kubeadm-lab uncordon kubeadm-lab
kubectl --context kubeadm-lab get nodes
#   kubeadm-lab   Ready   control-plane   9m34s   v1.37.0
```
Restarting the kubelet restarts the static Pods, so the API server is unreachable for a few seconds.

---

## Useful commands
```bash
kubeadm upgrade plan ; kubeadm upgrade apply v1.37.x ; kubeadm upgrade node
kubectl drain <node> --ignore-daemonsets ; kubectl uncordon <node>
apt-mark showhold ; apt-cache madison kubeadm
```

## Cleanup
The upgrade can't be undone in place. To start over: `minikube delete -p kubeadm-lab && ../start-kubeadm-lab.sh v1.36.0`. Otherwise keep the profile for the next kubeadm labs, or `minikube stop -p kubeadm-lab`.
