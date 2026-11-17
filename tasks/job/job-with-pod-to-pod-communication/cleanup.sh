#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete -f example-job.yaml --ignore-not-found
