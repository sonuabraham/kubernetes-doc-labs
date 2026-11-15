#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f . --ignore-not-found --now 2>/dev/null
kubectl delete pod curl --ignore-not-found --now
minikube profile list 2>/dev/null | grep -q probe-lab && minikube delete -p probe-lab
true
