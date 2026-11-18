#!/usr/bin/env bash
# Remove everything this lab created on the default cluster, and the agg-lab profile if it exists.
D=$(cd "$(dirname "$0")" && pwd)
"$D/../../../concepts/extend-kubernetes/api-extension/apiserver-aggregation/cleanup.sh"
minikube profile list 2>/dev/null | grep -q agg-lab && minikube delete -p agg-lab
true
