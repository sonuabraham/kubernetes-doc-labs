#!/usr/bin/env bash
kubectl delete devicetaintrule example preview --ignore-not-found
"$(dirname "$0")"/../../../scheduling-eviction/delete-ns.sh dra-taint
kubectl delete resourceslice fake-1-dra.example.com --ignore-not-found
kubectl delete deviceclass dra.example.com --ignore-not-found
