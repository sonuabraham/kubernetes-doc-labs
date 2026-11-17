#!/usr/bin/env bash
# Remove everything this lab created (metrics-server addon stays enabled).
kubectl delete pod load-generator --ignore-not-found --now
kubectl delete hpa php-apache --ignore-not-found
kubectl delete -f php-apache.yaml --ignore-not-found
