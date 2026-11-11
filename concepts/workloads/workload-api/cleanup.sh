#!/usr/bin/env bash
# Clean up the workload-api labs on the wl-lab cluster.
kubectl --context wl-lab delete namespace some-ns gang-demo training policy-demo ns-1 --ignore-not-found
kubectl --context wl-lab delete workloads,compositepodgroups,podgroups,pods --all -n default --ignore-not-found
kubectl --context wl-lab delete priorityclass high-priority --ignore-not-found
