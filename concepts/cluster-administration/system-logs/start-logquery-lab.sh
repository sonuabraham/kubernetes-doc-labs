#!/usr/bin/env bash
# Reuses/creates profile "swap-lab" (any throwaway profile works) and turns on the kubelet's system log query
# (enableSystemLogQuery: true; NodeLogQuery is GA). Restarts the kubelet.
set -euo pipefail
P=${P:-swap-lab}
minikube start -p $P --memory 2048 --cpus 2 --kubernetes-version v1.37.0 >/dev/null
minikube -p $P ssh -- "sudo sh -c 'f=/var/lib/kubelet/config.yaml; sed -i \"/^enableSystemLogQuery/d\" \$f; echo \"enableSystemLogQuery: true\" >> \$f; systemctl restart kubelet'"
sleep 10
kubectl --context $P get --raw /api/v1/nodes/$P/proxy/configz | jq -c '.kubeletconfig | {enableSystemLogQuery, enableSystemLogHandler}'
