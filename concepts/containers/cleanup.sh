#!/usr/bin/env bash
kubectl delete namespace containers-demo --ignore-not-found
minikube image rm local/hello:v1 local/hello:v2 >/dev/null 2>&1
