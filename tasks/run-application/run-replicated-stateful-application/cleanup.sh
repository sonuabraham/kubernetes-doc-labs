#!/usr/bin/env bash
# Remove everything this lab created (the docs' cleanup steps). The converted xtrabackup image stays cached in minikube.
kubectl delete pod mysql-client mysql-client-loop mysql-loop mysql-w --ignore-not-found --now
kubectl delete statefulset mysql --ignore-not-found
kubectl wait --for=delete pod -l app=mysql --timeout=120s 2>/dev/null || true
kubectl delete configmap,service,pvc -l app=mysql --ignore-not-found
kubectl uncordon minikube >/dev/null 2>&1 || true
