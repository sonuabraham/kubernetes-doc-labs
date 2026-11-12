#!/usr/bin/env bash
# Deleting a CRD deletes every object of that type too.
kubectl delete ns cr-demo --ignore-not-found
kubectl delete crd shirts.stable.example.com backups.demo.example.com --ignore-not-found
kubectl delete clusterrole shirts-backups-view --ignore-not-found
