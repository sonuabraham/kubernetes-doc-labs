#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f working-set-demo.yaml --ignore-not-found --now
