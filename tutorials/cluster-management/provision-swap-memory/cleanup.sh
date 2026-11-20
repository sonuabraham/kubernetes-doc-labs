#!/usr/bin/env bash
# Cleanup: demo Pods, then stop the throwaway profile swap-lab (its kubelet keeps LimitedSwap) and bring the default cluster back.
cd "$(dirname "$0")"
kubectl --context swap-lab delete -f swap-demo.yaml --ignore-not-found --now
minikube stop -p swap-lab
minikube start
