#!/usr/bin/env bash
# Cleanup (the page has none). Orphan the Pod first, then delete it with --grace-period=1: a Pod that is already terminating
# (e.g. after a cascading Deployment delete) keeps its 120 s grace period and the delete waits for it.
kubectl delete deployment nginx-deployment --cascade=orphan --ignore-not-found
kubectl delete rs -l app=nginx --cascade=orphan --ignore-not-found
kubectl delete pod -l app=nginx --grace-period=1 --ignore-not-found
kubectl delete service nginx-service --ignore-not-found
