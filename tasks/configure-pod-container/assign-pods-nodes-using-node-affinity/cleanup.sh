#!/usr/bin/env bash
# Pods (some sit on fake nodes -> force delete), the disktype label, and the fake nodes.
cd "$(dirname "$0")"
kubectl delete pod nginx nginx-preferred terms-or exprs-and not-in $(kubectl get pods -o name | grep -E 'nginx-(pref|noaff)-' | sed 's|pod/||') \
  --ignore-not-found --grace-period=0 --force 2>/dev/null
kubectl label nodes minikube disktype- 2>/dev/null
../../../concepts/scheduling-eviction/fake-nodes.sh down
