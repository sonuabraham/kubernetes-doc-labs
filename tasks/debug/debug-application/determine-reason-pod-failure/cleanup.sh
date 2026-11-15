#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f termination.yaml -f termination-variants.yaml --ignore-not-found --now
