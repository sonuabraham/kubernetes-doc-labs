#!/usr/bin/env bash
# set-kubelet.sh pod|container - on the rm-lab profile: enable PodLevelResourceManagers in the kubelet config,
# set topologyManagerScope, and restart the kubelet. (CPU/memory manager state checkpoints are cleared because the
# kubelet refuses to start when the policy/scope changes under existing state - drain-equivalent for a lab node.)
set -euo pipefail
SCOPE=${1:-pod}
minikube -p rm-lab ssh -- "sudo sh -c '
  f=/var/lib/kubelet/config.yaml
  grep -q \"^featureGates:\" \$f || echo \"featureGates: {}\" >> \$f
  sed -i \"s/^featureGates:.*/featureGates:\n  PodLevelResourceManagers: true/\" \$f
  sed -i \"/^topologyManagerScope:/d\" \$f; echo \"topologyManagerScope: $SCOPE\" >> \$f
  systemctl stop kubelet; rm -f /var/lib/kubelet/cpu_manager_state /var/lib/kubelet/memory_manager_state; systemctl start kubelet'"
sleep 15
kubectl --context rm-lab get --raw /api/v1/nodes/rm-lab/proxy/configz | jq -c '.kubeletconfig | {featureGates, topologyManagerScope, cpuManagerPolicy, memoryManagerPolicy}'
