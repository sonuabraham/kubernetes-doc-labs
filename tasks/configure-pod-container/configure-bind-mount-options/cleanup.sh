#!/usr/bin/env bash
kubectl delete pod emptydir-mode-demo bind-mount-options-demo --ignore-not-found --now
minikube profile list 2>/dev/null | grep -q volopt-lab && minikube delete -p volopt-lab
true
