#!/usr/bin/env bash
kubectl delete -f "$(dirname "$0")"/01-json-scheduler.yaml --ignore-not-found >/dev/null
minikube stop -p swap-lab >/dev/null 2>&1; kubectl config use-context minikube >/dev/null
