#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl --context minikube delete namespace kc-demo --ignore-not-found
rm -rf generated          # lab kubeconfigs, copied admin cert/key, plugin log
