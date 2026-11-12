#!/usr/bin/env bash
kubectl delete namespace sched-harden --ignore-not-found
kubectl delete clusterrolebinding sched-debug-reader my-scheduler-as-kube-scheduler my-scheduler-as-volume-scheduler --ignore-not-found
kubectl delete clusterrole sched-debug-reader --ignore-not-found
kubectl delete rolebinding my-scheduler-auth-reader -n kube-system --ignore-not-found
