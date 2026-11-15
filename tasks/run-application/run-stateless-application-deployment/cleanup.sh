#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete deployment nginx-deployment --ignore-not-found
