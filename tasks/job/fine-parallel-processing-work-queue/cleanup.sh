#!/usr/bin/env bash
# Remove everything this lab created (the job-wq-2 image stays cached in minikube: `minikube image rm job-wq-2`).
kubectl delete job job-wq-2 job-wq-crash --ignore-not-found
kubectl delete pod temp --ignore-not-found --now
kubectl delete -f redis-pod.yaml -f redis-service.yaml --ignore-not-found
