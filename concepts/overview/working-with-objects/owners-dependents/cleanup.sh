#!/usr/bin/env bash
kubectl delete namespace owners-demo owners-other --ignore-not-found
kubectl delete clusterrole child-cr --ignore-not-found
