#!/usr/bin/env bash
kubectl delete namespace vsc-demo --ignore-not-found
kubectl delete volumesnapshotclass csi-hostpath-retain --ignore-not-found
# Retain-policy contents outlive their snapshots
kubectl get volumesnapshotcontent -o jsonpath='{range .items[?(@.spec.volumeSnapshotRef.namespace=="vsc-demo")]}{.metadata.name}{"\n"}{end}' | xargs -r kubectl delete volumesnapshotcontent
# restore the addon's class to how minikube created it (not default)
kubectl annotate volumesnapshotclass csi-hostpath-snapclass snapshot.storage.kubernetes.io/is-default-class- >/dev/null 2>&1
