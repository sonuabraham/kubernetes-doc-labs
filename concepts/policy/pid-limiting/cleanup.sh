#!/usr/bin/env bash
minikube stop -p pid-lab >/dev/null 2>&1      # or: minikube delete -p pid-lab
kubectl config use-context minikube >/dev/null
