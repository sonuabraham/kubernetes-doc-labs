#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete job job-pod-failure-policy-failjob job-pod-failure-policy-ignore job-no-policy \
  job-pod-failure-policy-config-issue job-backoff-limit-per-index-failindex --ignore-not-found
rm -f patch.yaml
