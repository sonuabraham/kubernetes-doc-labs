#!/usr/bin/env bash
minikube stop -p trace-lab >/dev/null 2>&1       # or: minikube delete -p trace-lab
kubectl config use-context minikube >/dev/null
