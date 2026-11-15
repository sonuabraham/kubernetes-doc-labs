#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f envars.yaml -f print-greeting.yaml --ignore-not-found --now
kubectl delete pod envtest --ignore-not-found --now
