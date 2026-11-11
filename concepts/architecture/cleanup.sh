#!/usr/bin/env bash
# Usage: ./cleanup.sh        -> delete the demo namespaces, remove the lab taint
#        ./cleanup.sh cluster -> also delete the arch-lab minikube profile and switch back to "minikube"
kubectl --context arch-lab taint node arch-lab node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null
kubectl --context arch-lab delete namespace arch-demo team-x --ignore-not-found
if [ "$1" = cluster ]; then
  minikube delete -p arch-lab
  kubectl config use-context minikube
fi
