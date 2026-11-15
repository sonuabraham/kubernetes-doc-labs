#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete pod shell-demo shell-demo-2 my-pod --ignore-not-found --now
