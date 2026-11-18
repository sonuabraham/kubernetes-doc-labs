#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete pod two-containers two-containers-init --ignore-not-found
