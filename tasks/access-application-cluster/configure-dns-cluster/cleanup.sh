#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete -f dns-check.yaml --ignore-not-found
kubectl delete pod dnscheck --ignore-not-found
