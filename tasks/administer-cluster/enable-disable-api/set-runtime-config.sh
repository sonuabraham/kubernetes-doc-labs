#!/usr/bin/env bash
# ./set-runtime-config.sh '<value>'   set kube-apiserver's --runtime-config on the api-lab node (edit the static Pod
# manifest; the kubelet restarts the API server), then wait until it answers again.
# ./set-runtime-config.sh ''          remove the flag again.                      (P=<profile>, default api-lab)
P=${P:-api-lab}; D=$(cd "$(dirname "$0")/.." && pwd)
VAL=$1
P=$P "$D/kubeadm/node.sh" "M=/etc/kubernetes/manifests/kube-apiserver.yaml
  [ -f /root/kube-apiserver.orig.yaml ] || cp \$M /root/kube-apiserver.orig.yaml
  sed -i \"/--runtime-config=/d\" \$M
  if [ -n \"$VAL\" ]; then sed -i \"s|^    - kube-apiserver\$|&\n    - --runtime-config=$VAL|\" \$M; fi
  grep -n -- --runtime-config \$M || echo no --runtime-config flag"
sleep 15
for i in $(seq 60); do
  kubectl --context "$P" get --raw /readyz >/dev/null 2>&1 && { echo "API server ready"; exit 0; }
  sleep 3
done
echo "API server NOT ready after ~3 min - check: minikube ssh -p $P -- sudo crictl ps -a --name kube-apiserver"; exit 1
