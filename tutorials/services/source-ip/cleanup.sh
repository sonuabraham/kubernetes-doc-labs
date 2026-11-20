#!/usr/bin/env bash
# Cleanup (the page's cleanup: delete the Services and the Deployment) + this lab's busybox Pod and the fake LB.
kubectl delete svc clusterip nodeport loadbalancer --ignore-not-found --timeout=60s
kubectl delete deployment source-ip-app --ignore-not-found
kubectl delete pod busybox --ignore-not-found --now
"$(dirname "$0")"/../../../tasks/access-application-cluster/create-external-load-balancer/run-fake-lb.sh stop
