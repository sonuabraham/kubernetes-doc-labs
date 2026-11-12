#!/usr/bin/env bash
"$(dirname "$0")"/../../../scheduling-eviction/delete-ns.sh dra-how
kubectl delete resourceslice gpu-slice-1 --ignore-not-found
kubectl delete deviceclass dra.example.com --ignore-not-found
kubectl label node fake-2 accelerator-type- >/dev/null 2>&1; true
