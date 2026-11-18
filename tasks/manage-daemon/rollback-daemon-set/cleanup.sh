#!/usr/bin/env bash
# Remove everything this lab created (ControllerRevisions are owned by the DaemonSet and go with it).
kubectl delete -f "$(dirname "$0")/demo-daemonset.yaml" --ignore-not-found
