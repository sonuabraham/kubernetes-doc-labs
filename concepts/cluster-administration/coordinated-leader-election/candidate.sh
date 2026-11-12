#!/usr/bin/env bash
# A toy leader-election client that speaks the coordinated-leader-election protocol.
#   ./candidate.sh <name> <emulationVersion> [binaryVersion]      (runs until killed)
# Every second it:
#   1. registers / keeps its LeaseCandidate  (leaseName demo-leader, strategy OldestEmulationVersion)
#   2. ACKs pings: when the API server sets spec.pingTime newer than spec.renewTime, it bumps renewTime
#   3. if it holds Lease demo-leader: renews it every 2s - unless spec.preferredHolder names someone
#      else, then it STEPS DOWN (stops renewing) so the lease expires and the controller hands it over.
# Kill it (kill <pid> / Ctrl-C) to simulate a crashed leader.
set -u
NAME=$1 EMU=$2 BIN=${3:-1.37.0}
NS=${NS:-cle-demo} LEASE=demo-leader
K="kubectl --context ${CTX:-cle-lab} -n $NS"
now(){ local t; t=$(date -u +%Y-%m-%dT%H:%M:%S.%N); echo "${t:0:26}Z"; }   # MicroTime: exactly 6 decimals
log(){ echo "$(date +%T) [$NAME] $*"; }
$K apply -f - >/dev/null 2>&1 <<EOF
apiVersion: coordination.k8s.io/v1beta1
kind: LeaseCandidate
metadata: {name: $NAME}
spec: {leaseName: $LEASE, binaryVersion: "$BIN", emulationVersion: "$EMU", strategy: OldestEmulationVersion, renewTime: "$(now)"}
EOF
log "registered as candidate (emulation $EMU, binary $BIN)"
role=""; last=0
while :; do
  IFS='|' read -r ping renew < <($K get leasecandidate $NAME -o jsonpath='{.spec.pingTime}|{.spec.renewTime}' 2>/dev/null; echo)
  if [ -n "$ping" ] && [[ "$ping" > "$renew" ]]; then
    $K patch leasecandidate $NAME --type merge -p "{\"spec\":{\"renewTime\":\"$(now)\"}}" >/dev/null 2>&1 && log "ack ping $ping"
  fi
  IFS='|' read -r holder pref < <($K get lease $LEASE -o jsonpath='{.spec.holderIdentity}|{.spec.preferredHolder}' 2>/dev/null; echo)
  if [ "$holder" = "$NAME" ] && { [ -z "$pref" ] || [ "$pref" = "$NAME" ]; }; then
    [ "$role" != leader ] && { role=leader; log "I AM THE LEADER"; }
    if [ $(( $(date +%s) - last )) -ge 2 ]; then
      $K patch lease $LEASE --type merge -p "{\"spec\":{\"renewTime\":\"$(now)\"}}" >/dev/null 2>&1; last=$(date +%s)
    fi
  elif [ "$holder" = "$NAME" ]; then
    [ "$role" != stepping-down ] && { role=stepping-down; log "preferredHolder=$pref -> stepping down (no more renewals)"; }
  else
    [ "$role" != follower ] && { role=follower; log "follower (leader: ${holder:-none})"; }
  fi
  sleep 1
done
