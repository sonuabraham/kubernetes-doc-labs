#!/usr/bin/env bash
# Namespace (PVC -> PV deleted too, reclaim policy is back to Delete) and the context's default namespace.
kubectl delete ns rwop-demo --ignore-not-found
kubectl config set-context --current --namespace=default
