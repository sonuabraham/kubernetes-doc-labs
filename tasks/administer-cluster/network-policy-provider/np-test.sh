#!/usr/bin/env bash
# ./np-test.sh <context>  - does this cluster's network plugin ENFORCE NetworkPolicy?
# nginx behind a Service; a client Pod WITH label access=true and one WITHOUT. Checked three times:
#   1. no policy               -> both reach nginx
#   2. default-deny ingress    -> neither does (only if policies are enforced!)
#   3. + allow access=true     -> only the labelled client does
set -u; C=${1:?context}; K="kubectl --context $C -n np-test"
kubectl --context $C create ns np-test >/dev/null 2>&1
$K create deployment nginx --image=nginx >/dev/null 2>&1; $K expose deployment nginx --port=80 >/dev/null 2>&1
for c in allowed:true denied:false; do
  $K run ${c%%:*} --image=busybox:1.36 --labels=access=${c#*:} --command -- sleep 3600 >/dev/null 2>&1; done
$K wait --for=condition=Ready pod --all --timeout=180s >/dev/null
$K rollout status deploy nginx --timeout=120s >/dev/null
check(){ printf '%-34s' "$1"; for p in allowed denied; do
  if $K exec $p -- wget -q -T 3 -O /dev/null http://nginx 2>/dev/null; then printf ' %s=reach' $p; else printf ' %s=BLOCKED' $p; fi; done; echo; }
check "1. no policy:"
$K apply -f - >/dev/null <<Y
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-ingress}
spec: {podSelector: {}, policyTypes: [Ingress]}
Y
sleep 5; check "2. default-deny-ingress:"
$K apply -f - >/dev/null <<Y
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: access-nginx}
spec:
  podSelector: {matchLabels: {app: nginx}}
  ingress: [{from: [{podSelector: {matchLabels: {access: "true"}}}]}]
Y
sleep 5; check "3. + allow from access=true:"
kubectl --context $C delete ns np-test --wait=false >/dev/null
