#!/usr/bin/env bash
kubectl delete namespace dp-demo --ignore-not-found
kubectl delete storageclass slow fast slow-hostpath fast-hostpath --ignore-not-found
