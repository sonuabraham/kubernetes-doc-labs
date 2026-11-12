#!/usr/bin/env bash
kubectl --context rm-lab delete namespace plrm-demo --ignore-not-found
minikube stop -p rm-lab >/dev/null 2>&1      # or: minikube delete -p rm-lab
kubectl config use-context minikube >/dev/null
