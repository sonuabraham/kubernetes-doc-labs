#!/usr/bin/env bash
"$(dirname "$0")"/../delete-ns.sh multi-sched
kubectl delete clusterrolebinding multi-sched-kube-scheduler multi-sched-volume-scheduler --ignore-not-found
kubectl delete rolebinding multi-sched-auth-reader -n kube-system --ignore-not-found
