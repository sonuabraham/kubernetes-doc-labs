#!/usr/bin/env bash
# Cleanup = the docs' commands (+ the ServiceAccount goes with the namespace).
kubectl delete namespace dra-tutorial --ignore-not-found
kubectl delete deviceclass gpu.example.com --ignore-not-found
kubectl delete clusterrole dra-example-driver-role --ignore-not-found
kubectl delete clusterrolebinding dra-example-driver-role-binding --ignore-not-found
kubectl delete priorityclass dra-driver-high-priority --ignore-not-found
# NOT in the docs: files the driver left on the node through its hostPath volumes
minikube ssh -- 'sudo rm -rf /var/lib/kubelet/plugins/gpu.example.com /var/run/cdi/k8s.gpu.example.com-gpu_common.yaml'
