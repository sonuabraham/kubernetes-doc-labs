#!/usr/bin/env bash
# Separate profile whose kubelet has a hard memory eviction threshold JUST below the node's current
# memory.available, so a ~1.5Gi allocation creates real MemoryPressure. The docker-driver node sees the HOST's
# memory (~30Gi here) - adjust THRESHOLD to your machine:
#   kubectl --context evict-lab get --raw /api/v1/nodes/evict-lab/proxy/stats/summary | jq '.node.memory.availableBytes/1073741824'
# (minikube's --extra-config=kubelet.eviction-hard=... was not applied to this existing profile, so the kubelet
#  config file is edited directly - fine for a throwaway profile.)
set -euo pipefail
THRESHOLD=${THRESHOLD:-29Gi}
minikube start -p evict-lab --memory 2048 --cpus 2 --kubernetes-version v1.37.0
minikube -p evict-lab ssh -- "sudo sed -i -e '/^evictionHard:/,/^[a-zA-Z]/{/^  /d}' -e 's/^evictionHard:.*/evictionHard:\n  memory.available: \"$THRESHOLD\"\n  nodefs.available: \"0%\"\n  imagefs.available: \"0%\"/' -e 's/^evictionPressureTransitionPeriod:.*/evictionPressureTransitionPeriod: 30s/' /var/lib/kubelet/config.yaml && sudo systemctl restart kubelet"
sleep 10
kubectl --context evict-lab get --raw /api/v1/nodes/evict-lab/proxy/configz | jq -c '.kubeletconfig | {evictionHard, evictionPressureTransitionPeriod}'
echo "When done: minikube stop -p evict-lab ; kubectl config use-context minikube"
