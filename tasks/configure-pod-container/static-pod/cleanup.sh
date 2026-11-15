#!/usr/bin/env bash
# Remove the lab's static Pod manifests from the node (NEVER the control-plane ones), undo web-hosted mode.
cd "$(dirname "$0")"
minikube ssh -- 'sudo rm -f /etc/kubernetes/manifests/static-web.yaml /etc/kubernetes/manifests/static-web.yaml.backup /etc/kubernetes/manifests/static-cm.yaml /tmp/static-web.yaml'
minikube ssh -- 'sudo test -f /var/lib/kubelet/config.yaml.lab-orig' && ./web-hosted.sh down
kubectl delete configmap some-config --ignore-not-found
