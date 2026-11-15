#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f default-securitycontext.yaml -f protect-psa-labels.yaml --ignore-not-found
kubectl delete -f legacy-workloads.yaml --ignore-not-found
kubectl delete clusterrole privileged-psp --ignore-not-found
