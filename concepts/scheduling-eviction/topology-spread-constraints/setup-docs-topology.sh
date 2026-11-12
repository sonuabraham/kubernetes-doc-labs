#!/usr/bin/env bash
# Rebuilds the page's example cluster on fake nodes: node1..node4 (zoneA: node1,node2 / zoneB: node3,node4),
# node5 in zoneC (for the nodeAffinity example), labelled with the page's custom keys "node" and "zone",
# plus three existing foo=bar Pods on node1, node2, node3 (the docs' starting state).
set -euo pipefail
cd "$(dirname "$0")"; ../fake-nodes.sh up 5 >/dev/null
z=(x zoneA zoneA zoneB zoneB zoneC)
for i in 1 2 3 4 5; do kubectl label node fake-$i node=node$i zone=${z[$i]} --overwrite >/dev/null; done
kubectl create ns tsc-demo --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in 1 2 3; do
  kubectl run existing-$i -n tsc-demo --image=registry.k8s.io/pause:3.1 --labels=foo=bar --overrides="{\"spec\":{\"nodeName\":\"fake-$i\"}}" >/dev/null
done
kubectl get nodes -L node,zone -l type=fake
