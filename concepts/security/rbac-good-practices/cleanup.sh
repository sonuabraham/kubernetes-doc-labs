#!/usr/bin/env bash
kubectl delete namespace rbac-demo --ignore-not-found
kubectl delete clusterrole,clusterrolebinding -l attacker-grant --ignore-not-found
kubectl delete pv sneaky-pv --ignore-not-found
kubectl get csr -o name | grep evil- | xargs -r kubectl delete
