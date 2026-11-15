#!/usr/bin/env bash
# NOT from the docs. ./enable-audit.sh <policy.yaml> [extra kube-apiserver flags...]   (profile audit-lab, created if missing)
# Does the page's "Log backend" steps on the minikube node:
#   policy -> /etc/kubernetes/audit-policy.yaml, logs -> /var/log/kubernetes/audit/audit.log,
#   the docs' two hostPath volumes + volumeMounts, the flags --audit-policy-file / --audit-log-path (+ extras),
#   always starting from the original manifest (backup in /root/kube-apiserver.orig.yaml). Then waits for /readyz.
# Extra flags with "webhook" in them also copy audit-webhook-config.yaml and start the toy receiver on the node.
set -euo pipefail
cd "$(dirname "$0")"
P=audit-lab; POL=${1:?policy file}; shift
minikube -p $P status >/dev/null 2>&1 || { minikube start -p $P --memory 2200 --cpus 2 --kubernetes-version v1.37.0; }
kubectl config use-context minikube >/dev/null 2>&1 || true
minikube -p $P cp "$POL" /etc/kubernetes/audit-policy.yaml >/dev/null
EXTRA=""
for f in "$@"; do EXTRA="$EXTRA\n    - $f"; done
if [[ "$*" == *webhook* ]]; then
  minikube -p $P cp audit-webhook-config.yaml /etc/kubernetes/audit-webhook.yaml >/dev/null
  minikube -p $P cp audit-webhook-receiver.py /usr/local/bin/audit-webhook-receiver.py >/dev/null
  minikube -p $P ssh -- 'sudo systemctl stop audit-webhook 2>/dev/null; sudo systemctl reset-failed audit-webhook 2>/dev/null; sudo rm -f /var/log/audit-webhook.jsonl
    sudo systemd-run --unit=audit-webhook python3 /usr/local/bin/audit-webhook-receiver.py >/dev/null'
  EXTRA="$EXTRA\n    - --audit-webhook-config-file=/etc/kubernetes/audit-webhook.yaml"
  WVOL="\n  - name: audit-webhook\n    hostPath:\n      path: /etc/kubernetes/audit-webhook.yaml\n      type: File"
  WMNT="\n    - mountPath: /etc/kubernetes/audit-webhook.yaml\n      name: audit-webhook\n      readOnly: true"
else WVOL=""; WMNT=""; fi
minikube -p $P ssh -- "M=/etc/kubernetes/manifests/kube-apiserver.yaml
  sudo test -f /root/kube-apiserver.orig.yaml || sudo cp \$M /root/kube-apiserver.orig.yaml
  sudo cp /root/kube-apiserver.orig.yaml /tmp/m.yaml
  sudo sed -i 's|^    - kube-apiserver\$|&\n    - --audit-policy-file=/etc/kubernetes/audit-policy.yaml\n    - --audit-log-path=/var/log/kubernetes/audit/audit.log$EXTRA|' /tmp/m.yaml
  sudo sed -i 's|^    volumeMounts:\$|&\n    - mountPath: /etc/kubernetes/audit-policy.yaml\n      name: audit\n      readOnly: true\n    - mountPath: /var/log/kubernetes/audit/\n      name: audit-log\n      readOnly: false$WMNT|' /tmp/m.yaml
  sudo sed -i 's|^  volumes:\$|&\n  - name: audit\n    hostPath:\n      path: /etc/kubernetes/audit-policy.yaml\n      type: File\n  - name: audit-log\n    hostPath:\n      path: /var/log/kubernetes/audit/\n      type: DirectoryOrCreate$WVOL|' /tmp/m.yaml
  sudo rm -rf /var/log/kubernetes/audit; sudo cp /tmp/m.yaml \$M; sudo grep -E -- '--audit' \$M"
sleep 15
for i in $(seq 60); do kubectl --context $P get --raw /readyz >/dev/null 2>&1 && { echo "API server ready"; exit 0; }; sleep 3; done
echo "API server NOT ready - minikube -p $P ssh -- sudo crictl ps -a --name kube-apiserver"; exit 1
