#!/usr/bin/env bash
# NOT from the docs. Throwaway profile "topo-lab" with the kubelet set up the way this page assumes:
#   cpuManagerPolicy static (reservedSystemCPUs "0"), memoryManagerPolicy Static, topologyManagerPolicy single-numa-node
#   kubeReserved 50Mi + systemReserved 256Mi = reservedMemory 306Mi on NUMA node 0 (minikube's evictionHard has no
#   memory.available, so the eviction part of the formula is 0 - see tasks/administer-cluster/memory-manager)
# and builds the toy device plugin + PodResources client image into the node.
# Stop the default cluster first (`minikube stop`): two clusters exhaust this host's inotify instances.
set -euo pipefail
cd "$(dirname "$0")"
P=topo-lab; N(){ P=$P ../../../administer-cluster/kubeadm/node.sh "$1"; }
minikube -p $P status >/dev/null 2>&1 || minikube start -p $P --memory 3000 --cpus 4 --kubernetes-version v1.37.0
kubectl config use-context minikube >/dev/null 2>&1 || true
N 'test -f /root/kubelet-config.orig.yaml || cp /var/lib/kubelet/config.yaml /root/kubelet-config.orig.yaml
   systemctl stop kubelet; cp /root/kubelet-config.orig.yaml /var/lib/kubelet/config.yaml
   rm -f /var/lib/kubelet/cpu_manager_state /var/lib/kubelet/memory_manager_state
   printf "cpuManagerPolicy: static\nreservedSystemCPUs: \"0\"\nmemoryManagerPolicy: Static\ntopologyManagerPolicy: single-numa-node\nkubeReserved: {cpu: \"500m\", memory: \"50Mi\"}\nsystemReserved: {cpu: \"500m\", memory: \"256Mi\"}\nreservedMemory:\n- numaNode: 0\n  limits:\n    memory: \"306Mi\"\n" >> /var/lib/kubelet/config.yaml
   systemctl reset-failed kubelet; systemctl start kubelet; sleep 8; systemctl is-active kubelet'
minikube -p $P image build -t toy-foo-plugin:1 ../../../../concepts/extend-kubernetes/compute-storage-net/device-plugins/toy-plugin/ >/dev/null
echo "topo-lab ready: kubectl --context topo-lab ..."
