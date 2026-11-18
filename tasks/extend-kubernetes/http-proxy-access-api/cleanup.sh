#!/usr/bin/env bash
# Remove everything this lab created (stop kubectl proxy with Ctrl+C).
kubectl delete deployment hello-app --ignore-not-found
