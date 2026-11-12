#!/usr/bin/env bash
# Restart the static control-plane Pods the kubeadm way: they're managed by the kubelet from
# /etc/kubernetes/manifests (not by the API server), so "kubectl delete pod" only recreates the mirror Pod.
# Move the manifests out, wait for the kubelet to stop them, move them back.  (P=<profile>, default kubeadm-lab)
D=$(cd "$(dirname "$0")" && pwd)
"$D/node.sh" 'mkdir -p /tmp/manifests-off && mv /etc/kubernetes/manifests/*.yaml /tmp/manifests-off/ &&
  until [ -z "$(crictl ps -q --name "kube-apiserver|kube-controller-manager|kube-scheduler|etcd")" ]; do sleep 2; done &&
  echo "all control-plane containers stopped" && mv /tmp/manifests-off/*.yaml /etc/kubernetes/manifests/ &&
  until crictl ps --name kube-apiserver -q | grep -q .; do sleep 2; done && echo "manifests back, apiserver container running"'
until kubectl --context ${P:-kubeadm-lab} get --raw /readyz >/dev/null 2>&1; do sleep 2; done; echo "API server ready"
