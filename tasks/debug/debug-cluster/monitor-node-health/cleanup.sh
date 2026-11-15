#!/usr/bin/env bash
# Remove NPD and everything it left behind: the KernelDeadlock node condition outlives the DaemonSet.
cd "$(dirname "$0")"
kubectl delete -f node-problem-detector-fixed.yaml -f node-problem-detector.yaml --ignore-not-found
kubectl delete configmap node-problem-detector-config -n kube-system --ignore-not-found
I=$(kubectl get node minikube -o json | jq '[.status.conditions[].type] | index("KernelDeadlock")')
[ "$I" != null ] && kubectl patch node minikube --subresource=status --type=json \
  -p "[{\"op\":\"test\",\"path\":\"/status/conditions/$I/type\",\"value\":\"KernelDeadlock\"},{\"op\":\"remove\",\"path\":\"/status/conditions/$I\"}]"
minikube ssh -- "sudo rm -f /var/log/lab-kern.log"
true
