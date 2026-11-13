#!/usr/bin/env bash
# Print each demo Pod's QoS class and the cpuset its container reports (CTX=nodepol-lab).
K="kubectl --context ${CTX:-nodepol-lab} -n cpu-demo"
$K wait --for=condition=Ready pod --all --timeout=120s >/dev/null
for p in guaranteed-int guaranteed-fraction burstable; do
  printf '%-20s %-11s %s\n' $p "$($K get pod $p -o jsonpath='{.status.qosClass}')" "$($K logs $p)"
done
