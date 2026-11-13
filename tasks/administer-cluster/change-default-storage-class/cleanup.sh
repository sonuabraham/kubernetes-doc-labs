#!/usr/bin/env bash
# Back to minikube's state: "standard" is the (only) default, no gold class, no demo claims/volumes.
cd "$(dirname "$0")"
kubectl delete ns sc-demo --ignore-not-found
kubectl delete pv static-pv --ignore-not-found
kubectl delete -f 01-gold-storageclass.yaml --ignore-not-found
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass
