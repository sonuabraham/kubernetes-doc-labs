#!/usr/bin/env bash
# New profile whose kube-apiserver runs the v1.37 binary but EMULATES v1.36 (and the controller-manager/scheduler too)
minikube start -p compat-lab --memory 2048 --cpus 2 --kubernetes-version v1.37.0 \
  --extra-config=apiserver.emulated-version=1.36 \
  --extra-config=controller-manager.emulated-version=1.36 \
  --extra-config=scheduler.emulated-version=1.36
kubectl --context compat-lab get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[]' | grep emulated
echo "When done: minikube stop -p compat-lab ; kubectl config use-context minikube"
