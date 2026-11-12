#!/usr/bin/env bash
kubectl delete namespace gate-demo --ignore-not-found
kubectl delete clusterrolebinding,clusterrole gate-demo-metrics-reader --ignore-not-found
