#!/usr/bin/env bash
# NOT from the docs: a THROWAWAY profile "ds-lab" whose SERVICES are dual-stack.
#   ./ds-lab.sh start | delete
# minikube 1.37 can't create a dual-stack cluster directly (its cert code rejects a dual --service-cluster-ip-range:
# "invalid CIDR address: 10.96.0.0/12,fd00:10:96::/112", and --network on Docker 29 fails to read the gateway). So: start a
# normal IPv4 cluster, then add an IPv6 Service range to kube-apiserver and kube-controller-manager (= "single-to-dual-stack
# conversion" of the Service side). Pods and nodes stay IPv4-only: the node container has no IPv6 network.
set -euo pipefail
P=ds-lab; K="kubectl --context $P"
case "${1:-}" in
start)
  minikube stop || true
  minikube start -p $P --memory 2200 --cpus 2 --kubernetes-version v1.37.0
  for c in kube-apiserver kube-controller-manager; do
    minikube -p $P ssh -- "sudo sed -i 's#--service-cluster-ip-range=10.96.0.0/12\$#--service-cluster-ip-range=10.96.0.0/12,fd00:10:96::/112#' /etc/kubernetes/manifests/$c.yaml"
  done
  minikube -p $P ssh -- "sudo grep service-cluster-ip-range /etc/kubernetes/manifests/kube-apiserver.yaml"
  until $K get servicecidr kubernetes -o jsonpath='{.spec.cidrs}' 2>/dev/null | grep -q fd00; do :; done
  $K get servicecidr ;;
delete)
  minikube delete -p $P; minikube start; kubectl config use-context minikube ;;
*) echo "usage: $0 start|delete"; exit 1 ;;
esac
