#!/usr/bin/env bash
# NOT from the docs – make AppArmor usable on a minikube (docker driver) node, profile "apparmor-lab".
# The node is a privileged container on the host kernel: AppArmor is in the kernel (Y), but the node has no securityfs mount and
# no apparmor_parser, so the kubelet reports "AppArmor is not enabled on the host". This mounts securityfs, installs the
# apparmor package (Debian) in the node, and restarts kubelet + containerd so both re-detect AppArmor.
# Profiles loaded later live in the HOST kernel; cleanup.sh unloads them (apparmor_parser -R).
set -euo pipefail
P=${P:-apparmor-lab}
minikube -p $P status >/dev/null 2>&1 || minikube start -p $P --memory 2048 --cpus 2 --kubernetes-version v1.37.0
minikube -p $P ssh -- 'sudo mountpoint -q /sys/kernel/security || sudo mount -t securityfs securityfs /sys/kernel/security
  test -x /sbin/apparmor_parser || { sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apparmor >/dev/null; }
  sudo systemctl restart containerd kubelet; ls /sys/kernel/security/apparmor | head -3; sudo /sbin/apparmor_parser --version | head -1'
