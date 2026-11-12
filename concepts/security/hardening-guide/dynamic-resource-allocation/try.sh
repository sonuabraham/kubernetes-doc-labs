#!/usr/bin/env bash
# try.sh <sa> <what: allocation|devices> [pod-bound]
#   Patches gpu-claim's status AS that ServiceAccount (its own token, no admin cert).
#   allocation = status.allocation (scheduler's job)   devices = status.devices (driver's job)
#   pod-bound  = use a token bound to a Pod on node minikube (carries the node association)
set -uo pipefail
SA=$1; WHAT=$2; N=dra-harden
SERVER=$(kubectl config view --context minikube --minify -o jsonpath='{.clusters[0].cluster.server}')
if [ "${3:-}" = pod-bound ]; then
  kubectl get pod $SA-pod -n $N >/dev/null 2>&1 || { kubectl run $SA-pod -n $N --image=busybox:1.36 --overrides="{\"spec\":{\"serviceAccountName\":\"$SA\"}}" -- sleep 3600 >/dev/null; kubectl wait --for=condition=Ready pod/$SA-pod -n $N >/dev/null; }
  T=$(kubectl create token $SA -n $N --bound-object-kind Pod --bound-object-name $SA-pod)
else T=$(kubectl create token $SA -n $N); fi
if [ "$WHAT" = allocation ]; then
  P='{"status":{"allocation":{"devices":{"results":[{"request":"gpu","driver":"dra.example.com","pool":"minikube","device":"gpu-0"}]},"nodeSelector":{"nodeSelectorTerms":[{"matchFields":[{"key":"metadata.name","operator":"In","values":["minikube"]}]}]}}}}'
else
  P='{"status":{"devices":[{"driver":"dra.example.com","pool":"minikube","device":"gpu-0","conditions":[{"type":"Ready","status":"True","reason":"Configured","message":"ok","lastTransitionTime":"2026-11-12T00:00:00Z"}]}]}}'
fi
KUBECONFIG=/dev/null kubectl --server=$SERVER --insecure-skip-tls-verify --token=$T patch resourceclaim gpu-claim -n $N --subresource=status --type=merge -p "$P" 2>&1 | sed 's/.*forbidden: //' | cut -c1-190
