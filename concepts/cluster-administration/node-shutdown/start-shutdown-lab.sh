#!/usr/bin/env bash
# Throwaway profile whose kubelet has graceful node shutdown ON (both settings must be non-zero):
#   shutdownGracePeriod 30s, shutdownGracePeriodCriticalPods 10s  (the page's example)
set -euo pipefail
minikube start -p shutdown-lab --memory 2048 --cpus 2 --kubernetes-version v1.37.0
minikube -p shutdown-lab ssh -- "sudo sh -c 'f=/var/lib/kubelet/config.yaml; sed -i \"/^shutdownGracePeriod/d\" \$f; printf \"shutdownGracePeriod: 30s\nshutdownGracePeriodCriticalPods: 10s\n\" >> \$f; systemctl restart kubelet'"
sleep 10
kubectl --context shutdown-lab get --raw /api/v1/nodes/shutdown-lab/proxy/configz | jq -c '.kubeletconfig | {shutdownGracePeriod, shutdownGracePeriodCriticalPods}'
minikube -p shutdown-lab ssh -- "systemd-inhibit --list --no-pager"
