#!/usr/bin/env bash
cd "$(dirname "$0")/out"
kubectl delete -f web-tcp-service.yaml,redis-leader-service.yaml,redis-replica-service.yaml,web-deployment.yaml,redis-leader-deployment.yaml,redis-replica-deployment.yaml --ignore-not-found
kubectl delete pod pival --ignore-not-found --now
