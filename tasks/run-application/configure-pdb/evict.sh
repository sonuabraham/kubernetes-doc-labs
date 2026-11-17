#!/usr/bin/env bash
# NOT from the docs: ask the Eviction API to evict one Pod (what kubectl drain does for each Pod).
#   ./evict.sh <pod> [namespace]
# Prints the API answer: Success, or the reason the eviction was refused (HTTP 429 = would violate a PDB).
POD=$1; NS=${2:-default}
kubectl create --raw "/api/v1/namespaces/$NS/pods/$POD/eviction" -f - <<JSON 2>&1 | sed 's/^Error from server/  refused/'
{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"$POD","namespace":"$NS"}}
JSON
echo
