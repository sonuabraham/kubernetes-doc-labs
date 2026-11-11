#!/usr/bin/env bash
# Usage: ./cleanup.sh   -> delete leases-demo and switch kube-controller-manager back to --leader-elect=false
kubectl --context arch-lab delete namespace leases-demo --ignore-not-found
minikube ssh -p arch-lab -n arch-lab -- "sudo sed -i 's/--leader-elect=true/--leader-elect=false/' /etc/kubernetes/manifests/kube-controller-manager.yaml"
