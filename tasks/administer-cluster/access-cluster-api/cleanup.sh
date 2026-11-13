#!/usr/bin/env bash
# The token Secret from token-access.sh (default namespace) and the work/ dir (flattened admin kubeconfig!).
cd "$(dirname "$0")"
kubectl delete secret default-token -n default --ignore-not-found
rm -rf work
