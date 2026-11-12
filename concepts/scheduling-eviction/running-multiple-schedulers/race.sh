#!/usr/bin/env bash
# race.sh [rounds] - two independent schedulers each get a 3-CPU Pod for the same 4-CPU fake node, created at the same time
P(){ echo "{\"apiVersion\":\"v1\",\"kind\":\"Pod\",\"metadata\":{\"name\":\"$1\",\"namespace\":\"multi-sched\"},\"spec\":{\"schedulerName\":\"$2\",\"nodeSelector\":{\"kubernetes.io/hostname\":\"fake-3\"},\"containers\":[{\"name\":\"c\",\"image\":\"busybox:1.36\",\"resources\":{\"requests\":{\"cpu\":\"3\"}}}]}}"; }
for r in $(seq 1 ${1:-5}); do
  kubectl delete pod race-a race-b -n multi-sched --grace-period=0 --force >/dev/null 2>&1; sleep 2
  P race-a indep-a | kubectl create -f - >/dev/null & P race-b indep-b | kubectl create -f - >/dev/null & wait; sleep 4
  echo "round $r: $(kubectl get pods race-a race-b -n multi-sched -o jsonpath='{range .items[*]}{.metadata.name}={.spec.nodeName} {end}')"
done
