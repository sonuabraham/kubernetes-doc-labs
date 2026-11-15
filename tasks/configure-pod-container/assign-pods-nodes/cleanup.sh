#!/usr/bin/env bash
# Pods in the default namespace (docs), the node label, and the fake nodes.
cd "$(dirname "$0")"
kubectl delete pod nginx nginx-nodename-mismatch --ignore-not-found --now
kubectl label nodes minikube disktype- 2>/dev/null
../../../concepts/scheduling-eviction/fake-nodes.sh down
