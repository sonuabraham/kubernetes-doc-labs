#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f dapi-envars-pod.yaml -f dapi-envars-container.yaml -f dapi-extras.yaml --ignore-not-found --now
