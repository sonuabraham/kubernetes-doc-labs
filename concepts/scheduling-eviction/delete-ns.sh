#!/usr/bin/env bash
# delete-ns.sh <namespace>...  - delete namespaces whose Pods may sit on fake nodes: start the namespace deletion,
# then keep force-deleting its Pods (no kubelet will ever confirm their termination) until the namespace is gone.
for ns in "$@"; do
  kubectl delete namespace "$ns" --ignore-not-found --wait=false >/dev/null
  while kubectl get namespace "$ns" >/dev/null 2>&1; do
    kubectl delete pods --all -n "$ns" --grace-period=0 --force >/dev/null 2>&1; sleep 2
  done
done
