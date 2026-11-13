#!/usr/bin/env bash
# Runs ON a kubeadm-lab node (copied there with "minikube cp"; used by upgrade-control-plane.sh and the
# upgrading-linux-nodes lab). The docs' apt steps for one version, e.g. 1.37.0:
#   pkg-upgrade.sh repo    1.37.0   point /etc/apt at pkgs.k8s.io core:/stable:/v1.37 (see ../change-package-repository)
#   pkg-upgrade.sh kubeadm 1.37.0   unhold, install kubeadm + kubectl =1.37.0-1.1, hold
#   pkg-upgrade.sh kubelet 1.37.0   unhold, install kubelet =1.37.0-1.1, hold; point minikube's drop-in at /usr/bin/kubelet;
#                                   daemon-reload + restart kubelet
set -e
V=$2; MINOR=${V%.*}
case $1 in
repo)
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v$MINOR/deb/Release.key | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$MINOR/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
  apt-get update >/dev/null && apt-cache madison kubeadm | head -1 ;;
kubeadm)
  apt-mark unhold kubeadm kubectl >/dev/null 2>&1 || true
  apt-get install -y kubeadm=$V-1.1 kubectl=$V-1.1 >/dev/null 2>&1
  apt-mark hold kubeadm kubectl; kubeadm version -o short ;;
kubelet)
  apt-mark unhold kubelet >/dev/null 2>&1 || true
  apt-get install -y kubelet=$V-1.1 >/dev/null 2>&1
  apt-mark hold kubelet
  # minikube's drop-in hard-codes its own kubelet binary; the package's /usr/bin/kubelet must win
  sed -i "s|^ExecStart=/var/lib/minikube/binaries/v[^/]*/kubelet|ExecStart=/usr/bin/kubelet|" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
  systemctl daemon-reload && systemctl restart kubelet && /usr/bin/kubelet --version ;;
*) echo "usage: $0 repo|kubeadm|kubelet <version>"; exit 1 ;;
esac
