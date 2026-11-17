#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete -f demo-workloads.yaml --ignore-not-found
