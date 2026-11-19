#!/usr/bin/env bash
# Cleanup for the "Updating Configuration via a ConfigMap" tutorial (docs cleanup commands + port-forwards).
pkill -f "kubectl port-forward service/configmap-(sidecar-)?service " 2>/dev/null || true
kubectl delete deployment configmap-volume configmap-env-var configmap-two-containers configmap-sidecar-container immutable-configmap-volume --ignore-not-found
kubectl delete service configmap-service configmap-sidecar-service --ignore-not-found
kubectl delete configmap sport fruits color company-name-20240312 company-name-20150801 --ignore-not-found
