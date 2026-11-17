#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete services example-service --ignore-not-found
kubectl delete deployment hello-world --ignore-not-found
