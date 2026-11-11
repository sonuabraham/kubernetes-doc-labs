#!/usr/bin/env bash
# Evict a pod through the Eviction API (what "kubectl drain" does for every pod).
# Usage: ./evict.sh <pod>      prints "evicted" or the API's refusal
NS=disruptions-demo
out=$(echo "{\"apiVersion\":\"policy/v1\",\"kind\":\"Eviction\",\"metadata\":{\"name\":\"$1\",\"namespace\":\"$NS\"}}" \
  | kubectl create --raw /api/v1/namespaces/$NS/pods/$1/eviction -f - 2>&1)
if echo "$out" | grep -q '"kind":"Status"' && echo "$out" | grep -q Success; then echo "$1: evicted"; else echo "$1: $out" | cut -c1-200; fi
