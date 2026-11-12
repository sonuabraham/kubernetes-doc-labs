#!/usr/bin/env bash
kubectl delete namespace sched-demo --ignore-not-found
kubectl delete clusterrolebinding verbose-scheduler-as-kube-scheduler verbose-scheduler-as-volume-scheduler --ignore-not-found
kubectl delete rolebinding verbose-scheduler-auth-reader -n kube-system --ignore-not-found
kubectl label node fake-2 lab/disk- >/dev/null 2>&1
# fake nodes are shared by the scheduling labs: ../fake-nodes.sh down  when you're done with the section
true
