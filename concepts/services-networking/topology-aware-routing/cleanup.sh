#!/usr/bin/env bash
kubectl delete namespace tar-demo --ignore-not-found
kubectl label node minikube topology.kubernetes.io/zone- topology.kubernetes.io/region- >/dev/null 2>&1
