#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f 04-test-setup.yaml --ignore-not-found --wait=false
kubectl delete -f 01-dra-binding-updater.yaml -f 02-dra-node-driver-status-updater.yaml -f 03-dra-multinode-status-updater.yaml --ignore-not-found
