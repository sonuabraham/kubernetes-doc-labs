#!/usr/bin/env bash
minikube stop -p evict-lab >/dev/null 2>&1      # or: minikube delete -p evict-lab
kubectl config use-context minikube >/dev/null
