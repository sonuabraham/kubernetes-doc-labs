#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete pod on-fake-node --grace-period=0 --force --ignore-not-found 2>/dev/null
../../../concepts/scheduling-eviction/fake-nodes.sh down
kubectl delete deployment web --ignore-not-found; kubectl delete service web --ignore-not-found
# if apiserver-down.sh was interrupted, put the API server back:
minikube ssh -- 'sudo test -f /root/kube-apiserver.yaml && sudo mv /root/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml; true'
