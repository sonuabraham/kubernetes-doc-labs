#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f nginx-policy.yaml --ignore-not-found
kubectl delete service nginx --ignore-not-found
kubectl delete deployment nginx --ignore-not-found
