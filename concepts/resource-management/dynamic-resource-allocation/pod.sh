#!/usr/bin/env bash
# pod.sh <name> template|claim <ref>  - a Pod in dra-demo using a ResourceClaimTemplate or an existing ResourceClaim
src="resourceClaimTemplateName: $3"; [ "$2" = claim ] && src="resourceClaimName: $3"
kubectl apply -f - >/dev/null <<Y
apiVersion: v1
kind: Pod
metadata: {name: $1, namespace: dra-demo}
spec:
  resourceClaims: [{name: gpu, $src}]
  containers: [{name: c, image: registry.k8s.io/pause:3.8, resources: {claims: [{name: gpu}]}}]
Y
