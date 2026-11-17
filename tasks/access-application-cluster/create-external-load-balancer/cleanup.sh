#!/usr/bin/env bash
# Remove everything this lab created. The fake LB controller must still run while the Service is deleted
# (otherwise its finalizer keeps the Service in Terminating), so stop it last.
cd "$(dirname "$0")" || exit 1
kubectl delete svc example-service --ignore-not-found --timeout=60s
kubectl delete -f example-deployment.yaml --ignore-not-found
./run-fake-lb.sh stop
rm -f ccm.log kubeconfig.minikube
