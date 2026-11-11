#!/usr/bin/env bash
# Usage: ./add-member.sh <podgroup> <pod-name>   -> create a pod that belongs to the PodGroup
kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $2, namespace: policy-demo}
spec:
  schedulingGroup: {podGroupName: $1}
  containers: [{name: c, image: registry.k8s.io/pause:3.10}]
YAML
