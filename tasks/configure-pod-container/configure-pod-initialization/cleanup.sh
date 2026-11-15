#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f init-containers.yaml -f init-order-and-failure.yaml --ignore-not-found --now
