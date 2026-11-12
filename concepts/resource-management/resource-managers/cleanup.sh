#!/usr/bin/env bash
kubectl --context rm-lab delete namespace rm-demo --ignore-not-found
# minikube stop -p rm-lab ; kubectl config use-context minikube      (rm-lab is reused by ../pod-level-resource-managers)
