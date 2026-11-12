#!/usr/bin/env bash
kubectl --context minikube delete namespace health-demo --ignore-not-found
# the gated profile: stop or delete it
minikube stop -p vh-lab >/dev/null 2>&1    # or: minikube delete -p vh-lab
kubectl config use-context minikube >/dev/null
