#!/usr/bin/env bash
# Usage: ./cleanup.sh   -> delete the lab namespaces and reset kubectl's namespace preference
kubectl config set-context --current --namespace=default >/dev/null
kubectl delete namespace development staging production com --ignore-not-found
