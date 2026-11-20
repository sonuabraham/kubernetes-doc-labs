#!/usr/bin/env bash
# Cleanup: the docs' namespace delete, then the throwaway profile plrm-lab; default cluster back.
kubectl --context plrm-lab delete namespace plrm-tutorial --ignore-not-found 2>/dev/null || true
minikube delete -p plrm-lab
minikube start
