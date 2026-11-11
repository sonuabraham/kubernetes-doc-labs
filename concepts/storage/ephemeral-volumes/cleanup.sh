#!/usr/bin/env bash
kubectl delete namespace eph-demo --ignore-not-found
kubectl delete storageclass scratch-storage-class --ignore-not-found
