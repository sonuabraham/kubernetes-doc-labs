#!/usr/bin/env bash
"$(dirname "$0")"/../delete-ns.sh prio-demo
kubectl delete priorityclass high-priority high-priority-nonpreempting low-priority --ignore-not-found
