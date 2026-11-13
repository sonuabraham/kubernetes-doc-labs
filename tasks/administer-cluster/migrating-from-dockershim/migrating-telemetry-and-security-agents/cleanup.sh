#!/usr/bin/env bash
# Remove the demo agent from both clusters, plus the empty DIRECTORY that 01's untyped hostPath creates on a node
# without Docker (it would make later checks think a docker.sock exists).
cd "$(dirname "$0")"
for c in rt-lab minikube; do kubectl --context $c delete ns agents-demo --ignore-not-found; done
P=minikube ../node.sh '[ -d /var/run/docker.sock ] && rmdir /var/run/docker.sock && echo "removed stray /var/run/docker.sock dir"; true'
