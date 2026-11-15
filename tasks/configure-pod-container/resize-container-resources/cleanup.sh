#!/usr/bin/env bash
kubectl delete namespace qos-example --ignore-not-found
kubectl delete priorityclass resize-high resize-low --ignore-not-found 2>/dev/null
minikube profile list 2>/dev/null | grep -q resize-lab && minikube delete -p resize-lab
kubectl config use-context minikube
