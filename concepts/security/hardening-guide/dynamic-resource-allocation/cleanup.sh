#!/usr/bin/env bash
kubectl delete namespace dra-harden --ignore-not-found
kubectl delete deviceclass example-gpu --ignore-not-found
kubectl delete clusterrolebinding dra-status-only dra-allocator dra-node-driver dra-multi-driver --ignore-not-found
kubectl delete clusterrole dra-status-only dra-binding-updater dra-node-driver-status-updater dra-multinode-status-updater --ignore-not-found
