#!/usr/bin/env bash
kubectl --context shutdown-lab delete pod regular --ignore-not-found 2>/dev/null; kubectl --context shutdown-lab delete pod critical -n kube-system --ignore-not-found 2>/dev/null
minikube stop -p shutdown-lab >/dev/null 2>&1
kubectl config use-context minikube >/dev/null
"$(dirname "$0")"/../../scheduling-eviction/delete-ns.sh shutdown-demo
"$(dirname "$0")"/../../scheduling-eviction/fake-nodes.sh down >/dev/null
