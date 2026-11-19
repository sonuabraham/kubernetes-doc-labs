#!/usr/bin/env bash
# Cleanup for the AppArmor lab: Pods, the docs profile in the (host) kernel, the throwaway minikube profile.
# Pods confined by the docs' deny-write profile can't be killed (no signal rule, see README), so the profile is first
# replaced by deny-write-fixed.profile; then the Pods can terminate and the profile is unloaded.
cd "$(dirname "$0")"
P=${P:-apparmor-lab}
if minikube -p $P status >/dev/null 2>&1; then
  minikube -p $P cp deny-write-fixed.profile /tmp/deny-write-fixed.profile
  minikube -p $P ssh -- 'sudo /sbin/apparmor_parser -r /tmp/deny-write-fixed.profile'
  kubectl --context $P delete pod hello-apparmor hello-apparmor-2 apparmor-types plain --ignore-not-found --now
  # profiles are kernel-wide (shared with the host): unload the docs profile
  minikube -p $P ssh -- 'echo -n k8s-apparmor-example-deny-write | sudo tee /sys/kernel/security/apparmor/.remove >/dev/null; sudo grep -c k8s-apparmor-example /sys/kernel/security/apparmor/profiles || echo "profile unloaded"'
fi
minikube delete -p $P
echo "now: minikube start   (default cluster + its kubectl context)"
