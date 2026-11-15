#!/usr/bin/env bash
# The docs work in the default namespace.
cd "$(dirname "$0")"
kubectl delete deployment hostnames --ignore-not-found
kubectl delete service hostnames --ignore-not-found
kubectl delete pod busybox --ignore-not-found --now
kubectl delete -f hairpin.yaml -f deny-hostnames.yaml --ignore-not-found --now
