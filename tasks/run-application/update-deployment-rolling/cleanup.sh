#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete pod avail-client --ignore-not-found --wait=false
kubectl delete service nginx-svc --ignore-not-found
kubectl delete deployment nginx-deployment --ignore-not-found
