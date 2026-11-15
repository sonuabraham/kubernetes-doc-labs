#!/usr/bin/env bash
# Everything ran on the throwaway profile audit-lab.
minikube -p audit-lab status >/dev/null 2>&1 && minikube delete -p audit-lab
kubectl config use-context minikube 2>/dev/null; true
