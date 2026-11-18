#!/usr/bin/env bash
# Remove everything this lab created: Pods, node labels, and the fake GPU capacity.
D=$(cd "$(dirname "$0")" && pwd)
kubectl delete pod example-vector-add example-vector-add-nfd gpu-req-eq-lim gpu-third --ignore-not-found --now
kubectl label node minikube gpu.gpu-vendor.example/installed-memory- feature.node.kubernetes.io/pci-10.present- accelerator- 2>/dev/null
"$D/gpu-capacity.sh" remove 2>/dev/null
true
