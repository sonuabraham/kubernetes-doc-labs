#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete hpa nginx-deployment --ignore-not-found
kubectl delete deployment nginx-deployment --ignore-not-found
