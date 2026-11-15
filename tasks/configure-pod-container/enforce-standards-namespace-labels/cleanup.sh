#!/usr/bin/env bash
# Delete the lab namespaces and REMOVE the audit/warn labels the docs' "--all" command put on every namespace.
kubectl delete namespace my-baseline-namespace my-existing-namespace psa-versions --ignore-not-found
kubectl label ns --all pod-security.kubernetes.io/audit- pod-security.kubernetes.io/warn- 2>/dev/null
kubectl get ns --show-labels
