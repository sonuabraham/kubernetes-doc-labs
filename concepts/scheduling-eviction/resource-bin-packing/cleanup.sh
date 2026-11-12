#!/usr/bin/env bash
"$(dirname "$0")"/../delete-ns.sh binpack-demo
kubectl delete clusterrolebinding binpack-demo-kube-scheduler binpack-demo-volume-scheduler --ignore-not-found
kubectl delete rolebinding binpack-demo-auth-reader -n kube-system --ignore-not-found
for n in fake-1 fake-2 fake-3; do for f in capacity allocatable; do for r in foo bar; do
  kubectl patch node $n --subresource=status --type=json -p "[{\"op\":\"remove\",\"path\":\"/status/$f/intel.com~1$r\"}]" >/dev/null 2>&1; done; done; done
true
