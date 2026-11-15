#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete pod secret-test-pod mypod mypod-missing mypod-json-400 mypod-json-256 env-single-secret envvars-multiple-secrets \
  envfrom-secret prod-db-client-pod test-db-client-pod prod-db-client-pod-fixed test-db-client-pod-fixed --ignore-not-found --wait=false
kubectl delete secret test-secret mysecret backend-user db-user prod-db-secret test-db-secret --ignore-not-found
kubectl delete serviceaccount prod-db-client --ignore-not-found
