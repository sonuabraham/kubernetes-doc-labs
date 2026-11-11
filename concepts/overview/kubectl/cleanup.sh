#!/usr/bin/env bash
kubectl uncordon minikube >/dev/null 2>&1
kubectl delete namespace kubectl-demo --ignore-not-found
rm -f /tmp/kubectl-lab-kubeconfig
