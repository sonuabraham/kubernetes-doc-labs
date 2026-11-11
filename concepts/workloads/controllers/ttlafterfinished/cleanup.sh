#!/usr/bin/env bash
kubectl patch job held -n ttl-demo --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1
kubectl delete namespace ttl-demo --ignore-not-found
