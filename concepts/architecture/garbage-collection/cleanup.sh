#!/usr/bin/env bash
# Usage: ./cleanup.sh  -> delete gc-demo and reset the kubelet image GC age on arch-lab
kubectl --context arch-lab delete namespace gc-demo --ignore-not-found
minikube ssh -p arch-lab -n arch-lab -- "sudo sed -i 's/^imageMaximumGCAge: .*/imageMaximumGCAge: 0s/' /var/lib/kubelet/config.yaml && sudo systemctl restart kubelet"
