#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete statefulset myapp --ignore-not-found
kubectl delete service myapp --ignore-not-found
kubectl delete pods,pvc -l app.kubernetes.io/name=MyApp --ignore-not-found
