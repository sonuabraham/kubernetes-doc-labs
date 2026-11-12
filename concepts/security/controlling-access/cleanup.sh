#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete namespace projectcaribou --ignore-not-found
kubectl delete csr bob --ignore-not-found
rm -rf generated
