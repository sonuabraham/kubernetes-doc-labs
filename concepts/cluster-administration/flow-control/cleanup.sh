#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f 00-noisy.yaml -f health-for-strangers.yaml -f list-events-default-service-account.yaml --ignore-not-found >/dev/null
