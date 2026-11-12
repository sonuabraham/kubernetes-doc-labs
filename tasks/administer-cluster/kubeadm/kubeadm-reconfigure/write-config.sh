#!/usr/bin/env bash
# Build the <config-file> for "kubeadm init phase ... --config" on the kubeadm-lab node: /root/kubeadm.yaml
#   = the node's InitConfiguration (advertiseAddress, bindPort 8443, node name - minikube keeps it in
#     /var/tmp/minikube/kubeadm.yaml)  +  the CURRENT ClusterConfiguration from the kubeadm-config ConfigMap.
# Without the InitConfiguration kubeadm would default bindPort to 6443 and break the API server (minikube uses 8443).
#   ./write-config.sh                  # plain
#   ./write-config.sh /root/patches    # also set InitConfiguration.patches.directory ("--patches" can't be mixed with --config)
D=$(cd "$(dirname "$0")/.." && pwd)
"$D/node.sh" 'K=$(ls -d /var/lib/minikube/binaries/*/kubectl | sort -V | tail -1)
  awk "/^---/{exit} {print}" /var/tmp/minikube/kubeadm.yaml > /root/kubeadm.yaml
  [ -n "'"$1"'" ] && printf "patches:\n  directory: %s\n" "'"$1"'" >> /root/kubeadm.yaml
  echo "---" >> /root/kubeadm.yaml
  $K -n kube-system get cm kubeadm-config -o jsonpath="{.data.ClusterConfiguration}" >> /root/kubeadm.yaml
  echo "wrote /root/kubeadm.yaml ($(grep -c . /root/kubeadm.yaml) lines)"
  grep -E "^kind:|bindPort|directory:|service-node-port|example.com" /root/kubeadm.yaml'
