#!/usr/bin/env bash
# pod.sh <name> <template> [nodeName]  - Pod in dra-api using a ResourceClaimTemplate
nn=""; [ -n "${3:-}" ] && nn="nodeSelector: {kubernetes.io/hostname: $3},"
kubectl apply -f - >/dev/null <<Y
apiVersion: v1
kind: Pod
metadata: {name: $1, namespace: ${NS:-dra-api}}
spec: {$nn resourceClaims: [{name: r, resourceClaimTemplateName: $2}], containers: [{name: c, image: registry.k8s.io/pause:3.8, resources: {claims: [{name: r}]}}]}
Y
