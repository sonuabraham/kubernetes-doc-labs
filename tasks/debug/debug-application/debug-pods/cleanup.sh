#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete validatingadmissionpolicybinding keep-pod-finalizers --ignore-not-found
kubectl delete validatingadmissionpolicy keep-pod-finalizers --ignore-not-found
kubectl patch pod stuck -n debug-pods-demo --type=json -p '[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null
kubectl delete namespace debug-pods-demo debug-pods-rc --ignore-not-found
