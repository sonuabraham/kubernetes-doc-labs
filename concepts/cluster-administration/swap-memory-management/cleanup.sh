#!/usr/bin/env bash
kubectl --context swap-lab delete -f "$(dirname "$0")"/01-pods.yaml --ignore-not-found >/dev/null 2>&1
minikube stop -p swap-lab >/dev/null 2>&1       # or: minikube delete -p swap-lab
kubectl config use-context minikube >/dev/null
