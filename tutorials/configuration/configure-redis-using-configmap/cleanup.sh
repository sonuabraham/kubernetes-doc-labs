#!/usr/bin/env bash
# Cleanup for "Configuring Redis using a ConfigMap" (the docs' cleanup command).
kubectl delete pod/redis configmap/example-redis-config --ignore-not-found
