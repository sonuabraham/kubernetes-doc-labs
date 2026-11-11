#!/usr/bin/env bash
kubectl delete namespace sc-demo --ignore-not-found
kubectl delete storageclass csi-default csi-wffc-retain csi-only-node-x local-storage --ignore-not-found
# Retained PVs (csi-wffc-retain, local-pv-1) survive their claims - delete them explicitly
kubectl get pv -o jsonpath='{range .items[?(@.spec.storageClassName=="csi-wffc-retain")]}{.metadata.name}{"\n"}{end}' | xargs -r kubectl delete pv
kubectl delete pv local-pv-1 --ignore-not-found
minikube ssh -- "sudo rm -rf /mnt/disks" >/dev/null 2>&1
# make sure minikube's "standard" is the (only) default again
kubectl annotate sc standard storageclass.kubernetes.io/is-default-class=true --overwrite >/dev/null
