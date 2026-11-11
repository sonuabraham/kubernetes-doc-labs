#!/usr/bin/env bash
# Applies the docs' pre-provisioned content (04-…) pointing at a REAL snapshot handle, adapted for minikube:
#   - placeholder snapshotHandle -> the handle of snap-demo/new-snapshot-test's content
#   - deletionPolicy Retain (it imports a snapshot another content also owns; Delete would destroy it)
#   - sourceVolumeMode removed (the addon's v6.1 CRDs don't have that field)
#   - label snapshot.storage.kubernetes.io/managed-by=minikube (node-deployment snapshotter only watches those)
set -euo pipefail
H=$(kubectl get volumesnapshotcontent "$(kubectl get volumesnapshot new-snapshot-test -n snap-demo -o jsonpath='{.status.boundVolumeSnapshotContentName}')" -o jsonpath='{.status.snapshotHandle}')
sed -e "s/7bdd0de3-aaeb-11e8-9aae-0242ac110002/$H/" -e 's/deletionPolicy: Delete/deletionPolicy: Retain/' -e '/sourceVolumeMode/d' \
    "$(dirname "$0")/04-volumesnapshotcontent-preprovisioned.yaml" | kubectl apply -f -
kubectl label volumesnapshotcontent new-snapshot-content-test snapshot.storage.kubernetes.io/managed-by=minikube --overwrite
echo "imported snapshot handle $H"
