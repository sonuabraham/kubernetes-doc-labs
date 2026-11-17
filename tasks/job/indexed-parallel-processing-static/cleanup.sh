#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete job indexed-job indexed-job-fail --ignore-not-found
