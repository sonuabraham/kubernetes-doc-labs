#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete cronjob hello --ignore-not-found
kubectl delete job hello-manual --ignore-not-found
