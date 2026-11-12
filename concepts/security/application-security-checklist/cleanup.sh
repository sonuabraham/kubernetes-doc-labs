#!/usr/bin/env bash
kubectl delete namespace appsec-demo appsec-client --ignore-not-found
kubectl delete pod c -n default --ignore-not-found
