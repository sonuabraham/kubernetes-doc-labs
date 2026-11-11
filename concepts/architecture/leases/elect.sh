#!/usr/bin/env bash
# Leader election on a Lease, the way client-go does it (simplified):
#  - every 2s: read the Lease (with its resourceVersion)
#  - if I hold it            -> renew (update renewTime)
#  - if it is free / expired -> try to take it (update holderIdentity, acquireTime,
#                               leaseTransitions+1)
#  - otherwise               -> stand by
# Updates carry the resourceVersion we read, so if two candidates race, the API
# server accepts ONE and rejects the other with a 409 Conflict (optimistic locking).
# Usage: ./elect.sh <candidate-name>      run 2-3 of these in separate terminals
ME=${1:?usage: $0 <candidate-name>}; NS=leases-demo; L=example-foo
while true; do
  obj=$(kubectl get lease $L -n $NS -o json) || { sleep 2; continue; }
  holder=$(jq -r '.spec.holderIdentity // ""' <<<"$obj")
  dur=$(jq -r '.spec.leaseDurationSeconds' <<<"$obj")
  renew=$(jq -r '.spec.renewTime // ""' <<<"$obj")
  now=$(date -u +%s); age=999
  [ -n "$renew" ] && age=$(( now - $(date -u -d "${renew%.*}Z" +%s) ))
  ts=$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)
  if [ "$holder" = "$ME" ]; then
    new=$(jq --arg t "$ts" '.spec.renewTime=$t' <<<"$obj"); action="renew"
  elif [ -z "$holder" ] || [ "$age" -gt "$dur" ]; then
    new=$(jq --arg me "$ME" --arg t "$ts" '.spec.holderIdentity=$me | .spec.acquireTime=$t | .spec.renewTime=$t | .spec.leaseTransitions=((.spec.leaseTransitions // -1)+1)' <<<"$obj"); action="acquire"
  else
    printf '%s %-8s standby  (leader=%s, renewed %ss ago)\n' "$(date +%T)" "$ME" "$holder" "$age"; sleep 2; continue
  fi
  if out=$(kubectl replace -f - <<<"$new" 2>&1); then
    [ "$action" = acquire ] && printf '%s %-8s *** became LEADER ***\n' "$(date +%T)" "$ME" || printf '%s %-8s leader   (renewed)\n' "$(date +%T)" "$ME"
  else
    printf '%s %-8s lost the race: %s\n' "$(date +%T)" "$ME" "$(grep -o 'the object has been modified' <<<"$out" || echo "$out")"
  fi
  sleep 2
done
