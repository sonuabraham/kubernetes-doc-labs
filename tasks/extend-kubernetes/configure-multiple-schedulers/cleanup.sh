#!/usr/bin/env bash
# Remove everything this lab created (the system:kube-scheduler ClusterRole is never modified by this lab).
D=$(cd "$(dirname "$0")" && pwd)
kubectl delete pod no-annotation annotation-default-scheduler annotation-second-scheduler second-scheduler-while-not-leader typo-scheduler --ignore-not-found --now
kubectl delete -f "$D/my-scheduler-leader-election-rbac.yaml" --ignore-not-found
kubectl delete -f "$D/my-scheduler.yaml" --ignore-not-found
kubectl -n kube-system delete lease my-scheduler --ignore-not-found
