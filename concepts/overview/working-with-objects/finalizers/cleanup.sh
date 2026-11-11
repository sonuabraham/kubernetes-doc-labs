#!/usr/bin/env bash
# Removes the lab's custom finalizers first (nothing else will), then deletes everything.
NS=finalizers-demo
for o in configmap/guarded secret/dependent; do
  kubectl patch $o -n $NS --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null
done
kubectl delete namespace $NS --ignore-not-found
kubectl delete pv finalizers-demo-pv --ignore-not-found
