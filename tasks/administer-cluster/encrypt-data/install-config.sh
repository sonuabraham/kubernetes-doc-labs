#!/usr/bin/env bash
# ./install-config.sh <config.yaml>
# Copy an EncryptionConfiguration to /etc/kubernetes/enc/enc.yaml on the encrypt-lab node, replacing the docs'
# placeholders with real keys that live ONLY on the node (never in this repo):
#   <BASE 64 ENCODED SECRET>   -> key1 = /root/enc-key1  (created once with: head -c 32 /dev/urandom | base64)
#   <KEY2>                     -> key2 = /root/enc-key2  (used by the rotation lab)
# File mode 600, root-owned: the docs' caution - only the API server's user may read key material.   (P=<profile>)
P=${P:-encrypt-lab}; D=$(cd "$(dirname "$0")/.." && pwd); F=${1:?config file}
minikube -p "$P" cp "$F" /tmp/enc-template.yaml >/dev/null
P=$P "$D/kubeadm/node.sh" "for k in 1 2; do [ -f /root/enc-key\$k ] || head -c 32 /dev/urandom | base64 > /root/enc-key\$k; done
  mkdir -p /etc/kubernetes/enc
  sed -e \"s|<BASE 64 ENCODED SECRET>|\$(cat /root/enc-key1)|\" -e \"s|<KEY2>|\$(cat /root/enc-key2)|\" /tmp/enc-template.yaml > /etc/kubernetes/enc/enc.yaml
  chmod 600 /etc/kubernetes/enc/enc.yaml
  ls -l /etc/kubernetes/enc/enc.yaml; grep -nE \"aescbc|identity|name: key\" /etc/kubernetes/enc/enc.yaml"
