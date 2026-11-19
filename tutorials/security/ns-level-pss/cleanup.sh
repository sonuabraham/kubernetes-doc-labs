#!/usr/bin/env bash
# Cleanup for "Apply Pod Security Standards at the Namespace Level" (docs: kind delete cluster; here everything ran on minikube).
kubectl delete ns example --ignore-not-found
kubectl delete pod nginx -n default --ignore-not-found
