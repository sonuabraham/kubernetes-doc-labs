#!/usr/bin/env bash
# Remove everything this lab created: the DaemonSet, the ssd labels, and the fake nodes.
D=$(cd "$(dirname "$0")" && pwd)
kubectl delete -f "$D/daemonset-label-selector.yaml" --ignore-not-found
kubectl label nodes minikube ssd- 2>/dev/null || true
CTX=minikube "$D/../../../concepts/scheduling-eviction/fake-nodes.sh" down
for n in fake-1 fake-2 fake-3; do kubectl delete pod -A --field-selector spec.nodeName=$n --force --grace-period=0 2>/dev/null; done; true   # DaemonSet Pods left on the deleted fake nodes
