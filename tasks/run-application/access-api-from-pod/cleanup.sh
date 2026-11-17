#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete pod api-curl api-proxy api-python --ignore-not-found --now
kubectl delete configmap incluster-script --ignore-not-found
kubectl delete -f rbac-pod-reader.yaml --ignore-not-found
