#!/usr/bin/env bash
# force-delete-on-fake.sh [namespace]  - Pods on fake nodes can't terminate normally (no kubelet confirms),
# so namespace deletion hangs on them. Force-delete them (optionally only in one namespace).
for n in $(kubectl get nodes -l type=fake -o name | cut -d/ -f2); do
  kubectl get pods ${1:+-n $1} ${1:--A} --field-selector spec.nodeName=$n -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name}{"\n"}{end}' 2>/dev/null |
  while read ns p; do [ -n "$p" ] && kubectl delete pod "$p" -n "$ns" --grace-period=0 --force >/dev/null 2>&1; done
done
true
