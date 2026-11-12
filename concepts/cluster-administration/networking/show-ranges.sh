#!/usr/bin/env bash
# The three address ranges of the cluster network model, read from the live cluster (read-only)
echo "== Pod network (controller-manager)"; kubectl get pod -n kube-system -l component=kube-controller-manager -o json | jq -r '.items[0].spec.containers[0].command[]' | grep -E 'cluster-cidr|allocate-node-cidrs|node-cidr-mask'
kubectl get nodes -o custom-columns=NODE:.metadata.name,PODCIDRS:.spec.podCIDRs,INTERNAL-IP:.status.addresses[0].address
echo "== Service network (API server + ServiceCIDR objects)"; kubectl get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[]' | grep service-cluster-ip-range
kubectl get servicecidrs ; kubectl get ipaddresses | head -4
echo "== CNI on the node"; minikube ssh -- "ls /etc/cni/net.d; ip -4 route | head -5"
