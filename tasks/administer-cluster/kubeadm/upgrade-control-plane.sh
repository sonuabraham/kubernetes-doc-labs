#!/usr/bin/env bash
# Prep for the node-upgrade labs: upgrade the kubeadm-lab CONTROL PLANE from 1.36 to ${1:-1.37.0}, non-interactively.
# This is the kubeadm-upgrade lab (../kubeadm-upgrade) condensed: pkgs.k8s.io repo -> kubeadm -> upgrade apply ->
# kubelet + kubectl -> point minikube's kubelet drop-in at /usr/bin/kubelet -> restart. (No drain: single control plane.)
set -e
V=${1:-1.37.0}; MINOR=${V%.*}; P=${P:-kubeadm-lab}
D=$(cd "$(dirname "$0")" && pwd)
minikube -p "$P" cp "$D/pkg-upgrade.sh" /tmp/pkg-upgrade.sh
"$D/node.sh" "set -o pipefail; bash /tmp/pkg-upgrade.sh repo $V && bash /tmp/pkg-upgrade.sh kubeadm $V &&
  PATH=\$(ls -d /var/lib/minikube/binaries/v* | sort -V | head -1):\$PATH /usr/bin/kubeadm upgrade apply v$V -y --ignore-preflight-errors=SystemVerification | tail -4 &&
  bash /tmp/pkg-upgrade.sh kubelet $V"
sleep 10; until kubectl --context "$P" get --raw /readyz >/dev/null 2>&1; do sleep 2; done
kubectl --context "$P" get nodes
