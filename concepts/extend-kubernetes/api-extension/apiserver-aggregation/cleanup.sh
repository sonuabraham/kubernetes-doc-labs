#!/usr/bin/env bash
# Remove the APIService FIRST: deleting the namespace while it points at a dead backend would block
# namespace deletion (the namespace controller needs full discovery).
kubectl delete apiservice v1.toys.example.com --ignore-not-found
kubectl delete clusterrolebinding toys-reader-devs --ignore-not-found
kubectl delete clusterrole toys-reader --ignore-not-found
kubectl delete ns agg-demo --ignore-not-found
