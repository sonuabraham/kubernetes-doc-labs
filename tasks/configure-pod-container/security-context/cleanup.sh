#!/usr/bin/env bash
# Delete everything the security-context lab created (default namespace, as in the docs) + the seccomp profiles on the node.
cd "$(dirname "$0")"
kubectl delete pod security-context-demo security-context-demo-2 security-context-demo-3 security-context-demo-4 \
  security-context-demo-3-root security-context-demo-4-root selinux-demo --ignore-not-found --now
kubectl delete -f seccomp-pods.yaml -f apparmor-pods.yaml -f procmount-pods.yaml -f fsgroup-change-policy.yaml --ignore-not-found --now
minikube ssh -- "sudo rm -f /var/lib/kubelet/seccomp/my-profiles/profile-allow.json /var/lib/kubelet/seccomp/my-profiles/profile-deny-mkdir.json; sudo rmdir /var/lib/kubelet/seccomp/my-profiles 2>/dev/null; true"
