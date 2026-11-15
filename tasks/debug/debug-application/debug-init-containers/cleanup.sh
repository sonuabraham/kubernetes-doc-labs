#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f init-debug-demo.yaml --ignore-not-found --now
kubectl delete service mydb --ignore-not-found
