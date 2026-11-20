#!/usr/bin/env bash
# Cleanup for the ZooKeeper tutorial. The docs only say "uncordon all nodes" and "delete the persistent storage";
# nothing was cordoned here (single node, evictions instead of drain). This deletes the objects and the PVCs (PVs go with them).
cd "$(dirname "$0")"
kubectl delete -f zookeeper-single-node.yaml --ignore-not-found
timeout 120 bash -c 'until [ -z "$(kubectl get pods -l app=zk -o name)" ]; do sleep 2; done'
kubectl delete pvc -l app=zk
