#!/usr/bin/env bash
# Separate profile so the main cluster's kubelet isn't changed: per-Pod PID limit 64, and 1000 PIDs reserved for the system.
minikube start -p pid-lab --memory 2048 --cpus 2 --kubernetes-version v1.37.0 \
  --extra-config=kubelet.pod-max-pids=64 --extra-config=kubelet.system-reserved=pid=1000
echo "When done: minikube stop -p pid-lab ; kubectl config use-context minikube"
