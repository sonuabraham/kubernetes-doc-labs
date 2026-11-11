#!/usr/bin/env bash
kubectl patch pod evict-me -n conditions-demo --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1
kubectl delete namespace conditions-demo --ignore-not-found
