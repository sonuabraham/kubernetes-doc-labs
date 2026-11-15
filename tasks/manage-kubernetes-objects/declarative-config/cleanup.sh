#!/usr/bin/env bash
kubectl delete deployment nginx-deployment merge-demo imp-web owner-demo --ignore-not-found
kubectl delete configmap -l app=prune-demo --ignore-not-found
kubectl delete secret prune-demo-set --ignore-not-found
