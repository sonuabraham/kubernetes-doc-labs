#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f share-process-namespace.yaml -f visibility-demo.yaml --ignore-not-found --now
