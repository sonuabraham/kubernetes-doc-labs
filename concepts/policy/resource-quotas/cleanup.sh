#!/usr/bin/env bash
kubectl delete namespace myspace pq-demo scope-demo foo-ns --ignore-not-found
kubectl delete priorityclass high medium low cluster-services --ignore-not-found
