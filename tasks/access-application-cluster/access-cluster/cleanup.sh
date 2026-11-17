#!/usr/bin/env bash
# Remove everything this lab created (stop a kubectl proxy you started yourself with Ctrl+C / kill).
kubectl delete -f default-token-secret.yaml --ignore-not-found
