#!/usr/bin/env bash
# NOT from the docs: measure downtime during an update.
# Exposes nginx-deployment as a Service, runs a client Pod that requests it every 0.1 s, triggers an image change,
# waits for the rollout, then counts failed requests.
#   ./availability-test.sh [RollingUpdate|Recreate|RollingUpdate+preStop]
# RollingUpdate+preStop also adds a 5 s preStop sleep, so a terminating Pod keeps serving until the endpoints update.
set -euo pipefail
STRATEGY=${1:-RollingUpdate}
kubectl expose deployment nginx-deployment --name=nginx-svc --port=80 2>/dev/null || true
if [ "$STRATEGY" = RollingUpdate+preStop ]; then
  kubectl patch deployment nginx-deployment -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxUnavailable":"25%","maxSurge":"25%"}},"template":{"spec":{"containers":[{"name":"nginx","lifecycle":{"preStop":{"sleep":{"seconds":5}}}}]}}}}'
elif [ "$STRATEGY" = Recreate ]; then
  kubectl patch deployment nginx-deployment --type=json -p='[{"op":"remove","path":"/spec/strategy/rollingUpdate"},{"op":"replace","path":"/spec/strategy/type","value":"Recreate"}]'
else
  kubectl patch deployment nginx-deployment -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxUnavailable":"25%","maxSurge":"25%"}},"template":{"spec":{"containers":[{"name":"nginx","lifecycle":null}]}}}}'
fi
kubectl rollout status deployment/nginx-deployment >/dev/null
kubectl delete pod avail-client --ignore-not-found --wait >/dev/null
kubectl run avail-client --image=busybox:1.36 --restart=Never -- sh -c \
  'while true; do if wget -q -T 1 -O /dev/null http://nginx-svc; then echo ok; else echo FAIL; fi; sleep 0.1; done'
kubectl wait --for=condition=Ready pod/avail-client --timeout=60s >/dev/null
until [ "$(kubectl logs avail-client | wc -l)" -ge 10 ]; do :; done
CUR=$(kubectl get deployment nginx-deployment -o jsonpath='{.spec.template.spec.containers[0].image}')
NEW=nginx:1.16.1; [ "$CUR" = "$NEW" ] && NEW=nginx:1.17.0
kubectl set image deployment/nginx-deployment nginx=$NEW
kubectl rollout status deployment/nginx-deployment >/dev/null
for _ in $(seq 20); do kubectl logs avail-client >/dev/null; done   # keep the client running a little longer
echo "strategy=$STRATEGY  image $CUR -> $NEW"
kubectl logs avail-client | sort | uniq -c
kubectl delete pod avail-client --wait=false >/dev/null
