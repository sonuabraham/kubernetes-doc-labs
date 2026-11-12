#!/usr/bin/env bash
# What add-ons does this cluster run? Groups kube-system (and addon) workloads into the page's categories. Read-only.
cat_of(){ case $1 in
  *kindnet*|*calico*|*cilium*|*flannel*|*weave*) echo "Networking & NetworkPolicy";;
  *coredns*|*kube-dns*) echo "Service Discovery";;
  *dashboard*) echo "Visualization & Control";;
  *metrics-server*|*kube-state-metrics*|*prometheus*) echo "Instrumentation";;
  *csi*|*storage-provisioner*|*snapshot*) echo "Infrastructure (storage)";;
  *kube-proxy*) echo "Core (node proxy)";;
  *etcd*|*kube-apiserver*|*kube-controller-manager*|*kube-scheduler*) echo "Control plane (not an add-on)";;
  *) echo "Other";; esac; }
kubectl get deploy,ds,sts -n kube-system -o json | jq -r '.items[] | "\(.kind) \(.metadata.name)"' | while read k n; do printf '%-32s %-12s %s\n' "$(cat_of $n)" "$k" "$n"; done | sort
echo; echo "minikube addons enabled: $(minikube addons list -o json 2>/dev/null | jq -r 'to_entries[] | select(.value.Status=="enabled") | .key' | tr '\n' ' ')"
