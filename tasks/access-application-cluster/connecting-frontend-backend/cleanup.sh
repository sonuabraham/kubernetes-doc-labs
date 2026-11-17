#!/usr/bin/env bash
# Remove everything this lab created (note: the backend Service is called "hello", not "backend").
kubectl delete services frontend hello --ignore-not-found
kubectl delete deployment frontend backend --ignore-not-found
kubectl delete -f frontend-configmap-variant.yaml --ignore-not-found
kubectl delete configmap frontend-nginx-conf --ignore-not-found
