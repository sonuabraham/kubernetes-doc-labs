#!/usr/bin/env bash
# NOT from the docs. ./use-admission-config.sh <file>   (profile psa-lab; created if missing)
# Copies <file> to /var/lib/minikube/certs/psa/<file> on the node (that directory is already mounted into the
# kube-apiserver static Pod) and points --admission-control-config-file at it. Switching files changes the
# manifest, so the kubelet restarts the API server. The original manifest is kept in /root/kube-apiserver.orig.yaml.
set -euo pipefail
cd "$(dirname "$0")"
F=${1:?config file}; P=psa-lab
minikube -p $P status >/dev/null 2>&1 || { minikube start -p $P --memory 2200 --cpus 2 --kubernetes-version v1.37.0; kubectl config use-context minikube >/dev/null 2>&1 || true; }
minikube -p $P ssh -- "sudo mkdir -p /var/lib/minikube/certs/psa"
minikube -p $P cp "$F" "/var/lib/minikube/certs/psa/$(basename "$F")"
minikube -p $P ssh -- "M=/etc/kubernetes/manifests/kube-apiserver.yaml
  sudo test -f /root/kube-apiserver.orig.yaml || sudo cp \$M /root/kube-apiserver.orig.yaml
  sudo cp /root/kube-apiserver.orig.yaml /tmp/m.yaml
  sudo sed -i 's|^    - kube-apiserver\$|&\n    - --admission-control-config-file=/var/lib/minikube/certs/psa/$(basename "$F")|' /tmp/m.yaml
  sudo cp /tmp/m.yaml \$M; sudo grep -n admission-control-config-file \$M"
sleep 15
for i in $(seq 60); do kubectl --context $P get --raw /readyz >/dev/null 2>&1 && { echo "API server ready"; exit 0; }; sleep 3; done
echo "API server NOT ready"; exit 1
