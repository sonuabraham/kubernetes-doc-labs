#!/usr/bin/env bash
# Restore rt-lab's original CNI config (backed up in Lab 1) and remove the demo namespace.
cd "$(dirname "$0")"
../node.sh '[ -f /root/1-k8s.conflist.bak ] && cp /root/1-k8s.conflist.bak /etc/cni/net.d/1-k8s.conflist && systemctl restart cri-docker; true'
kubectl --context rt-lab delete ns cni-demo --ignore-not-found
