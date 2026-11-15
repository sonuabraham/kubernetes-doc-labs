#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f envars-file-container.yaml -f syntax-cases.yaml --ignore-not-found --now
kubectl delete pod $(kubectl get pods -o name | grep '^pod/ef-' | cut -d/ -f2) --ignore-not-found --now 2>/dev/null
true
