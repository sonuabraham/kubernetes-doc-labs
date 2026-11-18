#!/usr/bin/env bash
# Remove everything this lab created (docs command).
kubectl delete ds fluentd-elasticsearch -n kube-system --ignore-not-found
