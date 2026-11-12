#!/usr/bin/env bash
# Plays the missing Windows kubelet for one job: Pods being deleted from the fake Windows nodes never
# finish terminating (nobody confirms), which blocks rollouts. This force-deletes exactly those Pods.
NS=${NS:-win-guide}
kubectl get pods -n "$NS" -o json | jq -r '.items[] | select(.metadata.deletionTimestamp and (.spec.nodeName // "" | startswith("win-"))) | .metadata.name' |
  xargs -r kubectl delete pod -n "$NS" --force --grace-period=0 2>&1 | grep -v "^Warning: Immediate"
