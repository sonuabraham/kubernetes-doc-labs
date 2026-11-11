#!/usr/bin/env bash
kubectl delete volumesnapshot new-snapshot-test -n default --ignore-not-found
kubectl delete namespace snap-demo --ignore-not-found
# Retain contents are left behind on purpose by their snapshots - delete them explicitly
kubectl delete volumesnapshotcontent test-content new-snapshot-content-test --ignore-not-found
