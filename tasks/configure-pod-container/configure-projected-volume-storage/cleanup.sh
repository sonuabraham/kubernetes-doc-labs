#!/usr/bin/env bash
kubectl delete pod test-projected-volume projected-all-sources --ignore-not-found --now
kubectl delete secret user pass --ignore-not-found
kubectl delete configmap app-config --ignore-not-found
