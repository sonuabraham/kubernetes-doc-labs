#!/usr/bin/env bash
"$(dirname "$0")"/../../../scheduling-eviction/delete-ns.sh dra-feat
kubectl delete resourceslice resourceslice-with-countersets resourceslice-with-devices resourceslice --ignore-not-found
kubectl delete deviceclass dra.example.com resource.example.com --ignore-not-found
