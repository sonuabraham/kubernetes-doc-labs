#!/usr/bin/env bash
# Remove the autoscaler, its ConfigMap (it outlives the Deployment) and RBAC; put CoreDNS back to minikube's 1 replica.
cd "$(dirname "$0")"
sed 's|<SCALE_TARGET>|Deployment/coredns|' dns-horizontal-autoscaler.yaml | kubectl delete -f - --ignore-not-found
kubectl delete configmap kube-dns-autoscaler -n kube-system --ignore-not-found
kubectl scale deployment coredns -n kube-system --replicas=1
