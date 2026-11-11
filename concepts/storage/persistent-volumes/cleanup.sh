#!/usr/bin/env bash
# Delete claims first so dynamically provisioned PVs (reclaim Delete) go away with them
kubectl delete namespace pv-demo foo --ignore-not-found
kubectl delete pv task-pv-volume pv-stable-dev pv-stable-prod pv0003 recycle-pv block-pv foo-pv --ignore-not-found
kubectl delete storageclass csi-expandable my-csi-plugin example-vol-default --ignore-not-found
minikube ssh -- "sudo rm -rf /tmp/data /tmp/pv-stable-dev /tmp/pv-stable-prod /tmp/recycle-pv /tmp/foo-pv" >/dev/null 2>&1
# The CSI addons are reused by the other storage labs. To remove them:
#   minikube addons disable csi-hostpath-driver; minikube addons disable volumesnapshots
