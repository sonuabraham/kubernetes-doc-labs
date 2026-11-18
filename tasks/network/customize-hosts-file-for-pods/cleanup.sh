#!/usr/bin/env bash
# Remove everything this lab created.
D=$(dirname "$0")
kubectl delete pod nginx --ignore-not-found --now
kubectl delete -f "$D/hostaliases-pod.yaml" -f "$D/hosts-extras.yaml" --ignore-not-found --now
