#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f deployment-patch.yaml -f deployment-retainkeys.yaml -f deployment.yaml --ignore-not-found
