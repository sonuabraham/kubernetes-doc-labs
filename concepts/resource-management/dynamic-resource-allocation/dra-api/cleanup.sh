#!/usr/bin/env bash
D="$(dirname "$0")"
"$D"/../../../scheduling-eviction/delete-ns.sh dra-api dra-admin
kubectl delete resourceslice cat-slice white-cat-slice --ignore-not-found
kubectl delete deviceclass resource.example.com --ignore-not-found
"$D"/../fake-dra.sh up >/dev/null       # restores the fake gpu.example.com DeviceClass (the docs' one replaced it)
