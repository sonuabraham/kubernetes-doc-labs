#!/usr/bin/env bash
# Cleanup (the page has none): switch back to the minikube context, remove the dev/prod contexts the walkthrough added to
# ~/.kube/config, and delete both namespaces (with everything in them).
kubectl config use-context minikube
kubectl config delete-context dev 2>/dev/null || true
kubectl config delete-context prod 2>/dev/null || true
kubectl delete namespace development production --ignore-not-found
