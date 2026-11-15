#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete pod kubernetes-downwardapi-volume-example kubernetes-downwardapi-volume-example-2 dapi-volume-extras --ignore-not-found --wait=false
