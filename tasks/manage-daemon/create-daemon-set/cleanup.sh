#!/usr/bin/env bash
# Remove everything this lab created: the DaemonSet (docs command), debug Pods, and the file it left on the node.
kubectl delete --cascade=foreground --ignore-not-found --now daemonsets/example-daemonset
kubectl get pods -o name | grep node-debugger | xargs -r kubectl delete --now
minikube ssh -- sudo rm -f /var/log/machine-id.log
