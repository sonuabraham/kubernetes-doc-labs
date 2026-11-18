#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete -f web-unnamed-port.yaml -f web-service.yaml --ignore-not-found
