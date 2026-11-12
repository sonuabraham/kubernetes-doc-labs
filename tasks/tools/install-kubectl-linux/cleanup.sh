#!/usr/bin/env bash
# Everything this lab created lives in this folder (plus a test ConfigMap).
cd "$(dirname "$0")"
kubectl delete cm kuberc-test -n default --ignore-not-found
rm -f bin/kubectl bin/kubectl-convert bin/*.sha256 bin/kubectl.bad && rmdir bin 2>/dev/null; true
