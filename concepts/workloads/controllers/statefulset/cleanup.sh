#!/usr/bin/env bash
kubectl delete namespace sts-demo --ignore-not-found
kubectl delete storageclass my-storage-class --ignore-not-found
