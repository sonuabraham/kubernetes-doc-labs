#!/usr/bin/env bash
# NOT from the docs – re-sign only apiserver.crt at the "offline" CA side (/root/pki-out from gen-all-certs.sh), adding the
# first Service ClusterIP (10.96.0.1 for the default 10.96.0.0/12) that in-cluster clients use via KUBERNETES_SERVICE_HOST.
# The node never needs ca.key: only the new apiserver.crt/.key are copied in, then the static Pod is restarted.
#   ../../production-environment/tools/kubeadm/machines.sh x cp2 "HOST_NAME=cp2 HOST_IP=172.30.0.3; $(cat reissue-apiserver.sh)"
set -euo pipefail
: "${HOST_NAME:?}" "${HOST_IP:?}"
cd /root/pki-out
SANS="DNS:$HOST_NAME,IP:$HOST_IP,DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc,DNS:kubernetes.default.svc.cluster,DNS:kubernetes.default.svc.cluster.local,IP:10.96.0.1"
openssl req -new -newkey rsa:2048 -nodes -keyout apiserver.key -out apiserver.csr -subj "/CN=kube-apiserver" 2>/dev/null
openssl x509 -req -in apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 -out apiserver.crt \
  -extfile <(printf 'keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=%s\n' "$SANS") 2>/dev/null
rm -f apiserver.csr
cp apiserver.crt apiserver.key /etc/kubernetes/pki/
# restart kube-apiserver: move its manifest out and back (the kubelet stops / recreates the static Pod)
mv /etc/kubernetes/manifests/kube-apiserver.yaml /root/; sleep 20; mv /root/kube-apiserver.yaml /etc/kubernetes/manifests/
export KUBECONFIG=/etc/kubernetes/admin.conf
sleep 5; until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 2; done
echo | openssl s_client -connect $HOST_IP:6443 2>/dev/null | openssl x509 -noout -ext subjectAltName
