#!/usr/bin/env bash
kubectl delete $(kubectl get pods -o name | grep node-debugger) --grace-period=0 --force 2>/dev/null
../../../../concepts/scheduling-eviction/fake-nodes.sh down
true
