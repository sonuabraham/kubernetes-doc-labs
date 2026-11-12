#!/usr/bin/env bash
"$(dirname "$0")"/../delete-ns.sh perf-demo
kubectl delete clusterrolebinding perf-demo-kube-scheduler perf-demo-volume-scheduler --ignore-not-found
kubectl delete rolebinding perf-demo-auth-reader -n kube-system --ignore-not-found
# back to the usual 3 fake nodes
"$(dirname "$0")"/../fake-nodes.sh down >/dev/null; "$(dirname "$0")"/../fake-nodes.sh up 3 >/dev/null
