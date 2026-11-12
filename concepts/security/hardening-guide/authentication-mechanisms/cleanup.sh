#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete csr carol --ignore-not-found
kubectl delete secret bootstrap-token-lab123 -n kube-system --ignore-not-found
rm -rf generated
