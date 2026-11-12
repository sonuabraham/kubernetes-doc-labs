#!/usr/bin/env bash
"$(dirname "$0")"/../../scheduling-eviction/delete-ns.sh as-demo
kubectl delete node -l pool=elastic --ignore-not-found
