#!/usr/bin/env bash
# Delete SampleDBs while the operator still runs (so finalizers complete), then the operator and the CRD.
kubectl delete sampledbs --all -A --timeout=180s 2>/dev/null
kubectl delete job --all -n db-demo --ignore-not-found >/dev/null 2>&1
kubectl delete ns db-demo --ignore-not-found
kubectl delete -f "$(dirname "$0")/01-operator.yaml" --ignore-not-found
kubectl delete crd sampledbs.sampledb.example.com --ignore-not-found
