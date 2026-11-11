#!/usr/bin/env bash
kubectl delete namespace vpa-demo --ignore-not-found
# to remove VPA itself: (cd autoscaler/vertical-pod-autoscaler && ./hack/vpa-down.sh)
