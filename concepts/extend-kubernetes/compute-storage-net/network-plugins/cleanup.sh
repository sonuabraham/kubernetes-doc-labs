#!/usr/bin/env bash
# Delete the demo namespace; make sure the bandwidth plugin is out of kindnet's chain again.
D=$(cd "$(dirname "$0")" && pwd)
kubectl delete ns cni-demo --ignore-not-found
minikube ssh -- "sudo test -f /var/lib/minikube/10-kindnet.conflist.orig" && "$D/bandwidth.sh" off || echo "kindnet conflist is original"
