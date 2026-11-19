#!/usr/bin/env bash
# Cleanup for the guestbook tutorial: the docs' four delete commands, then stop the fake LB controller (if it was started) –
# it has to be running while the LoadBalancer Service is deleted, to remove its cleanup finalizer.
kubectl delete deployment -l app=redis
kubectl delete service -l app=redis
kubectl delete deployment frontend --ignore-not-found
kubectl delete service frontend --ignore-not-found --timeout=60s
"$(dirname "$0")"/../../../tasks/access-application-cluster/create-external-load-balancer/run-fake-lb.sh stop
