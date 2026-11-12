#!/usr/bin/env bash
minikube stop -p enc-lab >/dev/null 2>&1     # or: minikube delete -p enc-lab
kubectl config use-context minikube >/dev/null
