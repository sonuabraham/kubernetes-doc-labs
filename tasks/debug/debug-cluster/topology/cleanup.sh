#!/usr/bin/env bash
# Everything ran on the throwaway profile topo-lab.
minikube -p topo-lab status >/dev/null 2>&1 && minikube delete -p topo-lab
kubectl config use-context minikube 2>/dev/null; true
