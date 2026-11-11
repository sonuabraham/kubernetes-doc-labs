#!/usr/bin/env bash
kubectl delete namespace dns-demo --ignore-not-found
kubectl delete pod busybox dns-example -n default --ignore-not-found      # the docs pods pinned to "default"
