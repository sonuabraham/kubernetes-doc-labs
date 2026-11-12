#!/usr/bin/env bash
"$(dirname "$0")"/../../scheduling-eviction/delete-ns.sh dra-admin-lab
kubectl delete clusterrolebinding,clusterrole dra-admin-lab-metrics --ignore-not-found
"$(dirname "$0")"/../../resource-management/dynamic-resource-allocation/fake-dra.sh down >/dev/null
