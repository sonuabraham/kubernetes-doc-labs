#!/usr/bin/env bash
# Cleanup (docs): delete the Secret, Deployments, Services and PVCs generated from kustomization.yaml.
cd "$(dirname "$0")" && kubectl delete -k ./ --ignore-not-found
