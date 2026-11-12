#!/usr/bin/env bash
# wl-lab context
"$(dirname "$0")"/../delete-ns.sh wap
kubectl delete priorityclass wap-low wap-high --ignore-not-found
