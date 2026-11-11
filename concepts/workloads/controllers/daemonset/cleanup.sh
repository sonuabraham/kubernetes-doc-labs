#!/usr/bin/env bash
kubectl delete -f daemonset.yaml --ignore-not-found
kubectl delete namespace ds-demo --ignore-not-found
kubectl label node minikube disk- >/dev/null 2>&1
