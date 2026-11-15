#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f prometheus.yaml --ignore-not-found
