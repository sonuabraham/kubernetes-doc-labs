#!/usr/bin/env bash
# Undo the certificates lab: cp1 back to kubeadm's own certs, cp2's external-CA cluster reset, default minikube restarted.
# (Delete ALL lab machines instead:  ../../production-environment/tools/kubeadm/machines.sh down)
cd "$(dirname "$0")"
M=../../production-environment/tools/kubeadm/machines.sh
if docker ps -q --filter name=kadm-cp1 | grep -q .; then
  # shared-cert variant still active? (manifest differs from the saved original)
  if $M x cp1 '[ -f /root/kube-apiserver.yaml.orig ] && ! cmp -s /root/kube-apiserver.yaml.orig /etc/kubernetes/manifests/kube-apiserver.yaml'; then
    $M x cp1 "MODE=undo; $(cat shared-apiserver-cert.sh)"
  fi
fi
if docker ps -q --filter name=kadm-cp2 | grep -q .; then
  $M x cp2 'kubeadm reset -f >/dev/null 2>&1; rm -rf /etc/kubernetes/* /etc/cni/net.d/* /root/pki-out /root/jane.*; echo "cp2 reset"'
  docker stop kadm-cp2 >/dev/null
fi
minikube start >/dev/null 2>&1 && kubectl config use-context minikube
