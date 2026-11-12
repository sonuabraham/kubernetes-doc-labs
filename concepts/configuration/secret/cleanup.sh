#!/usr/bin/env bash
kubectl delete namespace secret-demo --ignore-not-found
kubectl delete secret bootstrap-token-5emitj -n kube-system --ignore-not-found
