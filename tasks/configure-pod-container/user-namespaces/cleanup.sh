#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete pod userns userns-2 --ignore-not-found --now
kubectl delete -f userns-hostpath.yaml -f userns-write.yaml --ignore-not-found --now
kubectl delete ns userns-restricted --ignore-not-found
minikube ssh -- "sudo rm -rf /var/lab-root-only"
