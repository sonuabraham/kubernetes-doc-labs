#!/usr/bin/env bash
kubectl delete namespace kern-demo --ignore-not-found
minikube ssh -- "sudo rm -f /var/lib/kubelet/seccomp/profiles/deny-mkdir.json" >/dev/null 2>&1
