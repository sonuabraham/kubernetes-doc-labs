#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f lifecycle-events.yaml -f hook-behaviour.yaml --ignore-not-found --now
