#!/usr/bin/env bash
# Cleanup (docs: delete the Service and the Deployment). The fake LB controller must still run while the Service is deleted:
# it removes the service.kubernetes.io/load-balancer-cleanup finalizer. Then stop it.
cd "$(dirname "$0")"
LB=../../../tasks/access-application-cluster/create-external-load-balancer/run-fake-lb.sh
kubectl delete services my-service --ignore-not-found --timeout=60s
kubectl delete deployment hello-world --ignore-not-found
$LB stop
