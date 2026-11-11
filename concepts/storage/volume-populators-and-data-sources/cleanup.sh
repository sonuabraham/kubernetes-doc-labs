#!/usr/bin/env bash
kubectl delete namespace pop-demo ns1 --ignore-not-found        # PVCs; toy PVs (reclaim Delete) follow
kubectl delete pv -l populated-by=toy-populator --ignore-not-found
kubectl delete crd exampledatasources.example.storage.k8s.io --ignore-not-found
minikube ssh -- "sudo rm -rf /tmp/populated" >/dev/null 2>&1
