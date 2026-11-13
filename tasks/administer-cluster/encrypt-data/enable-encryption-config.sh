#!/usr/bin/env bash
# ./enable-encryption-config.sh [--auto-reload]
# The docs' "Use the new encryption configuration file" step on the encrypt-lab node: add to the kube-apiserver
# static Pod manifest
#   - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml   (+ --encryption-provider-config-automatic-reload=true)
#   - a volumeMount  enc -> /etc/kubernetes/enc (readOnly)
#   - a hostPath volume  enc: /etc/kubernetes/enc (DirectoryOrCreate)
# then wait for the API server. A backup of the original manifest is kept in /root. Idempotent.   (P=<profile>)
P=${P:-encrypt-lab}; D=$(cd "$(dirname "$0")/.." && pwd)
RELOAD=""; [ "$1" = --auto-reload ] && RELOAD=1
P=$P "$D/kubeadm/node.sh" "M=/etc/kubernetes/manifests/kube-apiserver.yaml
  [ -f /root/kube-apiserver.orig.yaml ] || cp \$M /root/kube-apiserver.orig.yaml
  cp /root/kube-apiserver.orig.yaml /tmp/m.yaml
  sed -i \"s|^    - kube-apiserver\$|&\n    - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml|\" /tmp/m.yaml
  if [ -n \"$RELOAD\" ]; then sed -i \"s|^    - --encryption-provider-config=.*|&\n    - --encryption-provider-config-automatic-reload=true|\" /tmp/m.yaml; fi
  sed -i \"s|^    volumeMounts:\$|&\n    - name: enc\n      mountPath: /etc/kubernetes/enc\n      readOnly: true|\" /tmp/m.yaml
  sed -i \"s|^  volumes:\$|&\n  - name: enc\n    hostPath:\n      path: /etc/kubernetes/enc\n      type: DirectoryOrCreate|\" /tmp/m.yaml
  cp /tmp/m.yaml \$M
  grep -n -E \"encryption-provider|name: enc|/etc/kubernetes/enc\" \$M"
sleep 15
for i in $(seq 60); do
  kubectl --context "$P" get --raw /readyz >/dev/null 2>&1 && { echo "API server ready"; exit 0; }
  sleep 3
done
echo "API server NOT ready - check: minikube ssh -p $P -- sudo crictl ps -a --name kube-apiserver"; exit 1
