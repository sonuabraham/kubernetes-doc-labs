#!/usr/bin/env bash
# ./setup-node.sh plugin            install lab-kms-plugin on the kms-lab node and run it as systemd unit "lab-kms-plugin"
#                                   (KEK file /etc/lab-kms/keys generated ON THE NODE: "<key_id> <base64 32 bytes>")
# ./setup-node.sh apiserver <cfg>   install <cfg> as /etc/kubernetes/enc/enc.yaml and wire kube-apiserver to it:
#                                   --encryption-provider-config(+automatic-reload), hostPath mounts for the config dir
#                                   AND the plugin's socket dir /var/run/kmsplugin (the API server runs in a container)
# ./setup-node.sh rotate            "rotate the KEK in the remote KMS": append a new key, which becomes current
P=${P:-kms-lab}; D=$(cd "$(dirname "$0")/.." && pwd); N(){ P=$P "$D/kubeadm/node.sh" "$1"; }
case $1 in
plugin)
  N 'systemctl stop lab-kms-plugin 2>/dev/null; systemctl reset-failed lab-kms-plugin 2>/dev/null; true'   # a running binary can't be overwritten
  minikube -p "$P" cp "$(dirname "$0")/lab-kms-plugin/lab-kms-plugin" /usr/local/bin/lab-kms-plugin >/dev/null
  N 'chmod 755 /usr/local/bin/lab-kms-plugin; mkdir -p /etc/lab-kms /var/run/kmsplugin
     [ -s /etc/lab-kms/keys ] || echo "kek-1 $(head -c 32 /dev/urandom | base64)" > /etc/lab-kms/keys; chmod 600 /etc/lab-kms/keys
     systemctl stop lab-kms-plugin 2>/dev/null; systemctl reset-failed lab-kms-plugin 2>/dev/null
     systemd-run --unit=lab-kms-plugin /usr/local/bin/lab-kms-plugin -listen unix:///var/run/kmsplugin/socket.sock -keys /etc/lab-kms/keys
     sleep 2; systemctl is-active lab-kms-plugin; ls -l /var/run/kmsplugin/' ;;
apiserver)
  minikube -p "$P" cp "${2:?config}" /tmp/enc.yaml >/dev/null
  N 'mkdir -p /etc/kubernetes/enc; cp /tmp/enc.yaml /etc/kubernetes/enc/enc.yaml; chmod 600 /etc/kubernetes/enc/enc.yaml
     M=/etc/kubernetes/manifests/kube-apiserver.yaml; [ -f /root/kube-apiserver.orig.yaml ] || cp $M /root/kube-apiserver.orig.yaml
     cp /root/kube-apiserver.orig.yaml /tmp/m.yaml
     sed -i "s|^    - kube-apiserver\$|&\n    - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml\n    - --encryption-provider-config-automatic-reload=true|" /tmp/m.yaml
     sed -i "s|^    volumeMounts:\$|&\n    - {name: enc, mountPath: /etc/kubernetes/enc, readOnly: true}\n    - {name: kmsplugin, mountPath: /var/run/kmsplugin}|" /tmp/m.yaml
     sed -i "s|^  volumes:\$|&\n  - {name: enc, hostPath: {path: /etc/kubernetes/enc, type: DirectoryOrCreate}}\n  - {name: kmsplugin, hostPath: {path: /var/run/kmsplugin, type: DirectoryOrCreate}}|" /tmp/m.yaml
     cp /tmp/m.yaml $M; grep -cE "encryption-provider|kmsplugin" $M'
  sleep 15
  for i in $(seq 60); do kubectl --context "$P" get --raw /readyz >/dev/null 2>&1 && { echo "API server ready"; exit 0; }; sleep 3; done
  echo "API server NOT ready"; exit 1 ;;
rotate)
  N 'n=$(( $(wc -l < /etc/lab-kms/keys) + 1 )); echo "kek-$n $(head -c 32 /dev/urandom | base64)" >> /etc/lab-kms/keys; cut -d" " -f1 /etc/lab-kms/keys | tr "\n" " "; echo "(last = current)"' ;;
*) echo "usage: $0 plugin | apiserver <config> | rotate"; exit 1 ;;
esac
