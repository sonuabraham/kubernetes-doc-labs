#!/usr/bin/env bash
# Remove the lab's objects. Pods bound to win-node can never be confirmed terminated (no kubelet); once the Node
# is gone, the pod garbage collector deletes them (~40 s). dl/ is gitignored; rm -r dl to free ~170 MB.
cd "$(dirname "$0")"
kubectl --context kubeadm-lab -n kube-system delete ds kube-proxy-windows --ignore-not-found --wait=false
./fake-win-node.sh down
