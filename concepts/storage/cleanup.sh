#!/usr/bin/env bash
kubectl delete namespace storage-demo --ignore-not-found
# The sub-labs share minikube's CSI addons; remove them when you're done with the whole section:
#   minikube addons disable csi-hostpath-driver ; minikube addons disable volumesnapshots
