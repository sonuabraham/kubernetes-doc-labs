#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f dependent-envars.yaml -f reference-sources.yaml --ignore-not-found --now
