#!/usr/bin/env bash
# Remove everything this lab created, including the generated manifests.
kubectl delete job -l jobgroup=jobexample --ignore-not-found
rm -rf ./jobs ./jobs.yaml
