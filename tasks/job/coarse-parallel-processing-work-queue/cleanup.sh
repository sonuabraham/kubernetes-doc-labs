#!/usr/bin/env bash
# Remove everything this lab created (the job-wq-1 image stays cached in minikube: `minikube image rm job-wq-1`).
kubectl delete job job-wq-1 job-wq-short --ignore-not-found
kubectl delete pod temp --ignore-not-found --now
kubectl delete -f rabbitmq-statefulset.yaml -f rabbitmq-service.yaml --ignore-not-found
