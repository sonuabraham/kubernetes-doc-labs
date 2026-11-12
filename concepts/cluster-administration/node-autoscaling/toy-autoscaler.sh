#!/usr/bin/env bash
# A toy node autoscaler (what Cluster Autoscaler / Karpenter do, in 40 lines), using fake nodes:
#   PROVISION: unschedulable Pods that target the pool (nodeSelector pool=elastic) → add a 4-CPU fake node "elastic-N"
#   CONSOLIDATE: an elastic node with no workload Pods for EMPTY_SECONDS → cordon + delete it
# Runs in the foreground; Ctrl-C to stop. Nodes are kept "Ready" by ../../scheduling-eviction/fake-nodes.sh's heartbeat style loop.
set -uo pipefail
EMPTY_SECONDS=${EMPTY_SECONDS:-30}; declare -A empty_since
mknode(){ n=elastic-$(date +%s)
  kubectl apply -f - >/dev/null <<Y
apiVersion: v1
kind: Node
metadata: {name: $n, labels: {type: fake, pool: elastic, kubernetes.io/hostname: $n}}
Y
  echo "$(date +%T) PROVISION $n (pending Pods: $1)"; }
heartbeat(){ now=$(date -u +%FT%TZ)
  for n in $(kubectl get nodes -l pool=elastic -o name); do kubectl patch $n --subresource=status --type=merge -p "{\"status\":{\"capacity\":{\"cpu\":\"4\",\"memory\":\"8Gi\",\"pods\":\"110\"},\"allocatable\":{\"cpu\":\"4\",\"memory\":\"8Gi\",\"pods\":\"110\"},\"conditions\":[{\"type\":\"Ready\",\"status\":\"True\",\"reason\":\"FakeKubelet\",\"message\":\"toy\",\"lastHeartbeatTime\":\"$now\",\"lastTransitionTime\":\"2026-01-01T00:00:00Z\"}]}}" >/dev/null 2>&1; done; }
while true; do
  heartbeat
  pending=$(kubectl get pods -A --field-selector status.phase=Pending -o json | jq -r '[.items[] | select(.spec.nodeName == null and .spec.nodeSelector.pool == "elastic") | select(any(.status.conditions[]?; .reason=="Unschedulable"))] | length')
  booting=$(kubectl get nodes -l pool=elastic -o json | jq '[.items[] | select((.status.conditions // []) | length == 0)] | length')
  [ "$pending" -gt 0 ] && [ "$booting" -eq 0 ] && mknode $pending
  for n in $(kubectl get nodes -l pool=elastic -o jsonpath='{.items[*].metadata.name}'); do
    used=$(kubectl get pods -A --field-selector spec.nodeName=$n -o json | jq '[.items[] | select(.metadata.ownerReferences[0].kind != "DaemonSet")] | length')
    if [ "$used" -eq 0 ]; then empty_since[$n]=${empty_since[$n]:-$(date +%s)}
      if [ $(( $(date +%s) - ${empty_since[$n]} )) -ge $EMPTY_SECONDS ]; then
        kubectl cordon $n >/dev/null; kubectl delete node $n >/dev/null; unset "empty_since[$n]"; echo "$(date +%T) CONSOLIDATE $n (empty ${EMPTY_SECONDS}s)"; fi
    else unset "empty_since[$n]"; fi
  done
  sleep 5
done
