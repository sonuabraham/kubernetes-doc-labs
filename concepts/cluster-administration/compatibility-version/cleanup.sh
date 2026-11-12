#!/usr/bin/env bash
minikube stop -p compat-lab >/dev/null 2>&1       # or: minikube delete -p compat-lab
kubectl config use-context minikube >/dev/null
