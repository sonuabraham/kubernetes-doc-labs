#!/usr/bin/env bash
# Everything ran on the throwaway profile psa-lab - delete it.
minikube -p psa-lab status >/dev/null 2>&1 && minikube delete -p psa-lab
kubectl config use-context minikube 2>/dev/null; true
