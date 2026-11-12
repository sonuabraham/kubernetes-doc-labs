#!/usr/bin/env bash
# Throwaway profile whose kubelet uses swap: memorySwap.swapBehavior LimitedSwap (failSwapOn is already false on minikube).
# The host has swap; the docker-driver node shares it.
set -euo pipefail
minikube start -p swap-lab --memory 2048 --cpus 2 --kubernetes-version v1.37.0
minikube -p swap-lab ssh -- "sudo sh -c 'f=/var/lib/kubelet/config.yaml; sed -i \"/^memorySwap/,/^[a-z]/{/^memorySwap/d;/^  /d}\" \$f; printf \"memorySwap:\n  swapBehavior: LimitedSwap\n\" >> \$f; systemctl restart kubelet'"
sleep 12
kubectl --context swap-lab get --raw /api/v1/nodes/swap-lab/proxy/configz | jq -c '.kubeletconfig | {failSwapOn, memorySwap}'
