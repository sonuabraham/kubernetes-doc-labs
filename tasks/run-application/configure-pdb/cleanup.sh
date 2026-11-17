#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete pdb zk-pdb zk-pdb-2 bare-max bare-pct bare-int --ignore-not-found
kubectl delete -f zk-standin.yaml --ignore-not-found
kubectl delete pod -l app=bare --ignore-not-found --wait=false
