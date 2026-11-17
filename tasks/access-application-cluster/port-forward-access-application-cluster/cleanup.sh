#!/usr/bin/env bash
# Remove everything this lab created (stop any kubectl port-forward you started with Ctrl+C).
kubectl delete rolebinding pf-user-port-forwarder --ignore-not-found
kubectl delete -f rbac-portforward.yaml --ignore-not-found
kubectl delete -f mongo-service.yaml -f mongo-deployment.yaml --ignore-not-found
