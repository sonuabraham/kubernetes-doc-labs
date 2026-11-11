#!/usr/bin/env bash
kubectl label node minikube accelerator- 2>/dev/null
kubectl delete namespace labels-demo --ignore-not-found
