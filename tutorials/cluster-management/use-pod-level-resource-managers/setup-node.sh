#!/usr/bin/env bash
# NOT from the docs – throwaway profile "plrm-lab" for this tutorial.
#   ./setup-node.sh start          minikube profile with --feature-gates=PodLevelResourceManagers=true (all components)
#   ./setup-node.sh scope pod      apply the docs' kubelet settings with topologyManagerScope pod (or: container)
# The kubelet settings are the docs' four lines, plus what the static CPU/Memory managers need to start at all on this node
# (from tasks/administer-cluster/memory-manager): reservedSystemCPUs, kube/systemReserved and a matching reservedMemory.
# Changing manager policies requires deleting their state files while the kubelet is stopped.
set -euo pipefail
P=plrm-lab
node() { minikube -p $P ssh -- "sudo sh -c '$1'"; }
case ${1:?start|scope} in
  start)
    minikube start -p $P --memory 6144 --cpus 4 --kubernetes-version v1.37.0 --feature-gates=PodLevelResourceManagers=true
    node 'cp /var/lib/kubelet/config.yaml /root/kubelet-config.orig.yaml' ;;
  scope)
    S=${2:?pod|container}
    cat > /tmp/plrm-kubelet-extra.yaml <<EOF
cpuManagerPolicy: "static"
memoryManagerPolicy: "Static"
topologyManagerScope: "$S"
topologyManagerPolicy: "single-numa-node"
# LAB: needed by the static managers on this node
reservedSystemCPUs: "0"
kubeReserved: {cpu: "500m", memory: "50Mi"}
systemReserved: {cpu: "500m", memory: "256Mi"}
reservedMemory:
- numaNode: 0
  limits:
    memory: "306Mi"
EOF
    minikube -p $P cp /tmp/plrm-kubelet-extra.yaml /tmp/plrm-kubelet-extra.yaml
    node 'systemctl stop kubelet; cat /root/kubelet-config.orig.yaml /tmp/plrm-kubelet-extra.yaml > /var/lib/kubelet/config.yaml
          rm -f /var/lib/kubelet/cpu_manager_state /var/lib/kubelet/memory_manager_state; systemctl reset-failed kubelet; systemctl start kubelet'
    sleep 10
    kubectl --context $P get --raw /api/v1/nodes/$P/proxy/configz | python3 -c 'import json,sys; k=json.load(sys.stdin)["kubeletconfig"]; print({x:k.get(x) for x in ["cpuManagerPolicy","memoryManagerPolicy","topologyManagerScope","topologyManagerPolicy","featureGates"]})' ;;
esac
