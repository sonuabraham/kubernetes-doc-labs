#!/usr/bin/env bash
# Cleanup for the Cassandra tutorial. Docs: delete the StatefulSet, sleep terminationGracePeriodSeconds (500 s!), delete the PVCs,
# delete the Service. Here: wait until the Pods are actually gone (17 s measured) instead of sleeping 500 s, and also delete the
# StorageClass "fast" from cassandra-statefulset.yaml (it has no app=cassandra label, so the docs' commands leave it behind).
kubectl delete statefulset -l app=cassandra
timeout 600 bash -c 'until [ -z "$(kubectl get pods -l app=cassandra -o name)" ]; do sleep 2; done'
kubectl delete persistentvolumeclaim -l app=cassandra
kubectl delete service -l app=cassandra
kubectl delete storageclass fast --ignore-not-found
