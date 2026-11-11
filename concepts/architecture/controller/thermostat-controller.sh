#!/usr/bin/env bash
# A tiny controller (control loop) for Thermostat objects, run OUTSIDE the
# cluster (the docs: "You can run your own controller ... externally").
# Every 3s, for each Thermostat:
#   1. read desired state (spec) and current state (status) from the API server
#   2. act: switch the "heater" ConfigMap on/off  (control VIA the API server)
#           and write the heater state to a local file (DIRECT control of an
#           "external system": /tmp/heater-<name>)
#   3. simulate the room: current moves 1 degree toward desired while heating/cooling
#   4. report current state back: patch .status (status subresource)
# Stop with Ctrl-C. It is level-based: restart it any time, it just reconciles again.
NS=${NS:-controller-demo}
echo "thermostat-controller watching namespace $NS (Ctrl-C to stop)"
while true; do
  for name in $(kubectl get thermostats -n "$NS" -o jsonpath='{.items[*].metadata.name}'); do
    obj=$(kubectl get thermostat "$name" -n "$NS" -o json)
    desired=$(jq -r '.spec.desiredTemperature' <<<"$obj")
    current=$(jq -r '.status.currentTemperature // 15' <<<"$obj")    # a cold room to start
    if   [ "$current" -lt "$desired" ]; then heater=on;  current=$((current+1))
    elif [ "$current" -gt "$desired" ]; then heater=off; current=$((current-1))
    else heater=idle; fi
    # managed resource #1: a ConfigMap (via the API server), owned by the Thermostat
    uid=$(jq -r .metadata.uid <<<"$obj")
    kubectl create configmap "heater-$name" -n "$NS" --from-literal=state=$heater --dry-run=client -o json \
      | jq --arg uid "$uid" --arg n "$name" '.metadata.ownerReferences=[{"apiVersion":"home.example.com/v1","kind":"Thermostat","name":$n,"uid":$uid,"controller":true}]' \
      | kubectl apply -f - >/dev/null
    # managed resource #2: something OUTSIDE the cluster
    echo "$heater" > "${TMPDIR:-/tmp}/heater-$name"
    # report current state
    kubectl patch thermostat "$name" -n "$NS" --subresource=status --type=merge \
      -p "{\"status\":{\"currentTemperature\":$current,\"heater\":\"$heater\"}}" >/dev/null
    printf '%s  %-12s desired=%-3s current=%-3s heater=%s\n' "$(date +%T)" "$name" "$desired" "$current" "$heater"
  done
  sleep 3
done
