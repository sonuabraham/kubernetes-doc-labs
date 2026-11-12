#!/usr/bin/env bash
D="$(dirname "$0")"
"$D"/../../scheduling-eviction/delete-ns.sh ksm-demo
kubectl delete -f "$D"/00-kube-state-metrics.yaml --ignore-not-found >/dev/null
"$D"/../../scheduling-eviction/fake-nodes.sh down >/dev/null
rm -f "$D"/ksm.txt
