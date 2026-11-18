#!/usr/bin/env bash
# Remove everything this lab created (cluster objects, the work/ directory with keys and certs).
cd "$(dirname "$0")" || exit 1
kubectl delete csr my-svc.my-namespace --ignore-not-found
kubectl delete namespace my-namespace --ignore-not-found
kubectl delete secret server --ignore-not-found; kubectl delete configmap example-serving-ca --ignore-not-found   # if created in default as in the docs
rm -rf work
