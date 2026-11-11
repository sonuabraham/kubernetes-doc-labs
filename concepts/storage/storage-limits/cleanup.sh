#!/usr/bin/env bash
kubectl delete namespace limits-demo --ignore-not-found
kubectl delete pv absent-pv --ignore-not-found
kubectl delete csidriver absent.csi.example.com --ignore-not-found
# undo the docs' patch on the addon's driver; drop any manual count (the kubelet re-registers the plugin anyway)
kubectl patch csidriver hostpath.csi.k8s.io --type=merge -p '{"spec":{"nodeAllocatableUpdatePeriodSeconds":null}}' >/dev/null 2>&1
kubectl patch csinode minikube --type=json -p '[{"op":"remove","path":"/spec/drivers/0/allocatable"}]' >/dev/null 2>&1
true
