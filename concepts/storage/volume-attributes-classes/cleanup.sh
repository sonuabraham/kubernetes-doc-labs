#!/usr/bin/env bash
kubectl delete namespace vac-demo --ignore-not-found
kubectl delete vac silver gold hostpath-silver hostpath-gold --ignore-not-found
