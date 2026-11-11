#!/usr/bin/env bash
kubectl delete namespace cap-demo --ignore-not-found
kubectl delete storageclass csi-hostpath-wffc --ignore-not-found
kubectl patch csidriver hostpath.csi.k8s.io --type=merge -p '{"spec":{"storageCapacity":true}}' >/dev/null 2>&1
