#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f nginx-with-request.yaml --ignore-not-found
kubectl delete pod ephemeral-demo myapp myapp-debug curl --ignore-not-found --now
kubectl delete $(kubectl get pods -o name | grep node-debugger) --now 2>/dev/null
kubectl delete namespace example-ns dbg-restricted --ignore-not-found
kubectl delete -f aggregate-ephemeralcontainers-edit.yaml -f debug-ephemeralcontainers.yaml --ignore-not-found
true
