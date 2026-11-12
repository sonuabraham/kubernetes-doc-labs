#!/usr/bin/env bash
cd "$(dirname "$0")"
./webhook-config.sh none
kubectl delete -f 01-final-state-vap.yaml --ignore-not-found >/dev/null
kubectl delete namespace hooked unhooked webhook-system --ignore-not-found
rm -rf generated
