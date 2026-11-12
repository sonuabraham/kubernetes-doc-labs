#!/usr/bin/env bash
# ./cleanup.sh [token]  - remove the fake Windows node, its CSRs, the bootstrap token and local credentials.
# (The kindnet nodeSelector patch from Lab 4 is harmless on Linux-only clusters and is left in place.)
cd "$(dirname "$0")"
K="kubectl --context kubeadm-lab"
$K delete node win-node --ignore-not-found
$K get csr -o name | grep node-csr-win-node | xargs -r $K delete
[ -n "$1" ] && ../node.sh "\$KUBEADM token delete ${1%%.*}"
rm -f ca.crt win-node.key win-node.csr win-node.crt
