#!/usr/bin/env bash
# Cleanup (the page has no cleanup section). Delete the LoadBalancer Service while the fake LB controller still runs
# (it removes the cleanup finalizer), then stop it. The converted images stay loaded in minikube (harmless).
kubectl delete svc my-nginx --ignore-not-found --timeout=60s
kubectl delete deployment my-nginx curl-deployment --ignore-not-found
kubectl delete secret nginxsecret --ignore-not-found
kubectl delete configmap nginxconfigmap --ignore-not-found
"$(dirname "$0")"/../../../tasks/access-application-cluster/create-external-load-balancer/run-fake-lb.sh stop
