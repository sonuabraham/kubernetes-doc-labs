#!/usr/bin/env bash
# Remove everything this lab created. APIService first (a dead backend blocks namespace deletion).
D=$(cd "$(dirname "$0")" && pwd)
kubectl delete apiservice v1alpha1.wardle.example.com --ignore-not-found
kubectl delete -f "$D/flunder-reader.yaml" --ignore-not-found
kubectl delete clusterrolebinding wardle-apiserver wardle-apiserver:system:auth-delegator --ignore-not-found
kubectl delete clusterrole wardle-apiserver --ignore-not-found
kubectl -n kube-system delete rolebinding wardle-apiserver-auth-reader --ignore-not-found
kubectl delete namespace wardle --ignore-not-found
