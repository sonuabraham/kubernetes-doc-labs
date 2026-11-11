#!/usr/bin/env bash
# Create a ConfigMap <dependent> in <dep-namespace> whose ownerReference points
# at an existing object (looked up to get its UID - a valid owner reference
# needs name AND uid).
# Usage: ./owner-ref.sh <owner-kind> <owner-name> <owner-namespace|-> <dependent> <dep-namespace|-> [blockOwnerDeletion]
#   ./owner-ref.sh configmap parent owners-demo child owners-demo
#   ./owner-ref.sh configmap parent owners-demo child owners-other        # cross-namespace (disallowed)
#   ./owner-ref.sh configmap parent owners-demo child-cr -                # cluster-scoped dependent (ClusterRole)
set -e
KIND=$1 NAME=$2 ONS=$3 DEP=$4 DNS=$5 BLOCK=${6:-false}
nsflag(){ [ "$1" = "-" ] && echo "" || echo "-n $1"; }
OBJ=$(kubectl get "$KIND" "$NAME" $(nsflag "$ONS") -o json)
REF=$(jq -c --argjson b "$BLOCK" '{apiVersion, kind, name: .metadata.name, uid: .metadata.uid, blockOwnerDeletion: $b}' <<<"$OBJ")
if [ "$DNS" = "-" ]; then
  kubectl create clusterrole "$DEP" --verb=get --resource=pods --dry-run=client -o json \
    | jq --argjson r "$REF" '.metadata.ownerReferences=[$r]' | kubectl apply -f -
else
  kubectl create configmap "$DEP" -n "$DNS" --from-literal=k=v --dry-run=client -o json \
    | jq --argjson r "$REF" '.metadata.ownerReferences=[$r]' | kubectl apply ${AS:+--as=$AS} -f -
fi
