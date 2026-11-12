#!/usr/bin/env bash
# A NEW profile (extra-config is applied at creation) whose kubelet runs:
#   CPU manager static (CPU 0 reserved), memory manager Static (reserved memory = kube-reserved + eviction threshold),
#   topology manager policy best-effort.
minikube start -p rm-lab --memory 4096 --cpus 4 --kubernetes-version v1.37.0 \
  --extra-config=kubelet.cpu-manager-policy=static \
  --extra-config=kubelet.reserved-cpus=0 \
  --extra-config=kubelet.kube-reserved=memory=256Mi \
  --extra-config=kubelet.eviction-hard=memory.available\<256Mi \
  --extra-config=kubelet.memory-manager-policy=Static \
  --extra-config=kubelet.reserved-memory=0:memory=512Mi \
  --extra-config=kubelet.topology-manager-policy=best-effort
echo "When done: minikube stop -p rm-lab ; kubectl config use-context minikube"
