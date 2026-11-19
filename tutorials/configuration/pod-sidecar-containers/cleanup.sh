#!/usr/bin/env bash
# Cleanup for the "Adopting Sidecar Containers" lab (all objects are NOT from the docs; the page has no manifests).
kubectl delete pod sidecar-start-order sidecar-termination universal-sidecar universal-sidecar-wait --ignore-not-found --now
kubectl delete job job-native-sidecar job-legacy-sidecar job-sidecar-restarts --ignore-not-found
