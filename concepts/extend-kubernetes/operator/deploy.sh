#!/usr/bin/env bash
# Installs the operator: CRD, then the code as a ConfigMap, then RBAC + Deployment.
D=$(cd "$(dirname "$0")" && pwd)
kubectl apply -f "$D/00-sampledb-crd.yaml"
kubectl wait --for=condition=Established crd/sampledbs.sampledb.example.com --timeout=30s
kubectl create ns sampledb-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create cm sampledb-operator-code -n sampledb-system --from-file="$D/sampledb_operator.py" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$D/01-operator.yaml"
kubectl rollout restart deploy/sampledb-operator -n sampledb-system >/dev/null 2>&1   # pick up code changes
kubectl rollout status deploy/sampledb-operator -n sampledb-system --timeout=120s
