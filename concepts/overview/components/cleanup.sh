#!/usr/bin/env bash
# Usage: ./cleanup.sh   -> delete the demo namespace (and make sure the
#                          controller-manager manifest is back in place)
minikube ssh -- 'sudo test -f /tmp/kube-controller-manager.yaml && sudo mv /tmp/kube-controller-manager.yaml /etc/kubernetes/manifests/ || true'
kubectl delete namespace components-demo --ignore-not-found
