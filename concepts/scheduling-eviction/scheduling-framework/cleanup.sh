#!/usr/bin/env bash
"$(dirname "$0")"/../delete-ns.sh fw-demo
kubectl delete clusterrolebinding fw-demo-configz-reader fw-demo-kube-scheduler fw-demo-volume-scheduler --ignore-not-found
kubectl delete clusterrole fw-demo-configz-reader --ignore-not-found
kubectl delete rolebinding fw-demo-auth-reader -n kube-system --ignore-not-found
kubectl delete priorityclass fw-low fw-high --ignore-not-found
for n in fake-1 fake-2 fake-3; do kubectl taint nodes $n dedicated- >/dev/null 2>&1; done
true
