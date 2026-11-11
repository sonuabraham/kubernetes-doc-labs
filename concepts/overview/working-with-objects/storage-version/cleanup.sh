#!/usr/bin/env bash
kubectl delete namespace storage-version-demo --ignore-not-found
kubectl delete storageversionmigration crontabs-to-v1 --ignore-not-found
kubectl delete crd crontabs.example.com --ignore-not-found
