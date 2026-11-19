#!/usr/bin/env bash
# Cleanup for the seccomp lab (docs: kind delete cluster). Here: Pods/Services on the default minikube, the profiles on its node,
# and the throwaway profile seccomp-lab used for --seccomp-default.
kubectl --context minikube delete service audit-pod fine-pod fine-pod-fixed --ignore-not-found
kubectl --context minikube delete pod default-pod audit-pod violation-pod fine-pod fine-pod-fixed alpine --ignore-not-found --now
minikube ssh -- 'sudo rm -rf /var/lib/kubelet/seccomp/profiles' 2>/dev/null || true
minikube delete -p seccomp-lab 2>/dev/null || true
