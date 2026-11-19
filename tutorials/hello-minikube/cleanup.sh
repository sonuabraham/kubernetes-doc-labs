#!/usr/bin/env bash
# The docs' cleanup (Service + Deployment). The dashboard addon was disabled before this lab, so it is disabled again.
# NOT done here: the docs' `minikube stop` / `minikube delete` - this minikube is shared by all labs in the repo.
kubectl delete service hello-node --ignore-not-found
kubectl delete deployment hello-node --ignore-not-found
minikube addons disable dashboard
