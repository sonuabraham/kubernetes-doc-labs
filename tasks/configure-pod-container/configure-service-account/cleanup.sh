#!/usr/bin/env bash
# Undo everything the ServiceAccount lab did in the default namespace.
cd "$(dirname "$0")"
kubectl delete pod nginx my-pod my-pod-override my-pod-inherit sa-default --ignore-not-found --now
kubectl patch pod sa-finalizer --type=json -p '[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null
kubectl delete pod sa-finalizer --ignore-not-found --now
kubectl delete secret build-robot-secret myregistrykey --ignore-not-found
kubectl delete serviceaccount build-robot --ignore-not-found
kubectl delete node node-001 --ignore-not-found
kubectl patch serviceaccount default --type=json -p '[{"op":"remove","path":"/imagePullSecrets"}]' 2>/dev/null
true
