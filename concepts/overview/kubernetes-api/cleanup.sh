#!/usr/bin/env bash
./proxy.sh stop
kubectl delete namespace api-demo --ignore-not-found
