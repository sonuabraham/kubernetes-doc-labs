#!/usr/bin/env bash
# Cleanup for the canary tutorial (docs cleanup commands + the curl client Pod used here).
kubectl delete deployment rollout-demo-stable rollout-demo-canary --ignore-not-found
kubectl delete service rollout-demo-service rollout-demo-stable-service rollout-demo-canary-service --ignore-not-found
kubectl delete httproute rollout-demo-route --ignore-not-found 2>/dev/null || true    # only if Gateway API CRDs exist
kubectl delete pod curl-client --ignore-not-found --now
