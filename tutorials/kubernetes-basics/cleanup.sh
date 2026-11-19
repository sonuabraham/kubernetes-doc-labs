#!/usr/bin/env bash
# Shared by all six modules: the docs' final cleanup (module 6) plus any leftovers if you stopped earlier.
kubectl delete deployments/kubernetes-bootcamp services/kubernetes-bootcamp --ignore-not-found
pkill -f "^kubectl proxy$" 2>/dev/null || true     # the proxy started in modules 2/3 (exact command line only)
