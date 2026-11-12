#!/usr/bin/env bash
"$(dirname "$0")"/../force-delete-on-fake.sh multi-sched
kubectl delete namespace multi-sched --ignore-not-found
kubectl delete clusterrolebinding multi-sched-kube-scheduler multi-sched-volume-scheduler --ignore-not-found
kubectl delete rolebinding multi-sched-auth-reader -n kube-system --ignore-not-found
