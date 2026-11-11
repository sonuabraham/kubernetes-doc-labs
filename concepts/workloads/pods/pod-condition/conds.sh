#!/usr/bin/env bash
# Print a pod's conditions as: TYPE=STATUS(reason) @lastTransitionTime
kubectl get pod "$1" -n conditions-demo -o jsonpath='{range .status.conditions[*]}{.type}={.status}({.reason}) @{.lastTransitionTime}{"\n"}{end}'
