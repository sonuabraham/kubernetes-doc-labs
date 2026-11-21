#!/usr/bin/env bash
# NOT from the docs – the page's "Shared Certificates" approach done so that it actually works.
# kubeadm's apiserver.crt has only "TLS Web Server Authentication", so the kubelet rejects it as a client certificate
# ("x509: certificate specifies an incompatible key usage"). A shared cert needs BOTH usages, and its CN needs kubelet API RBAC.
# Run as root on a kubeadm control-plane node (uses the cluster CA key in /etc/kubernetes/pki):
#   ../../production-environment/tools/kubeadm/machines.sh x cp1 "$(cat shared-apiserver-cert.sh)"
#   ... and to undo:  ... x cp1 "MODE=undo; $(cat shared-apiserver-cert.sh)"
set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
cd /etc/kubernetes/pki
MAN=/etc/kubernetes/manifests/kube-apiserver.yaml
wait_api() { sleep 10; until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 2; done; }
if [ "${MODE:-}" = undo ]; then
  cp /root/kube-apiserver.yaml.orig $MAN; wait_api
  kubectl delete clusterrolebinding lab:apiserver-shared-kubelet-client --ignore-not-found
  rm -f apiserver-shared.crt apiserver-shared.key apiserver-shared.csr; echo "restored"; exit 0
fi
[ -f /root/kube-apiserver.yaml.orig ] || cp $MAN /root/kube-apiserver.yaml.orig
# same subject + SANs as kubeadm's apiserver.crt, plus clientAuth
SAN=$(openssl x509 -in apiserver.crt -noout -ext subjectAltName | tail -1 | sed 's/ //g; s/IPAddress/IP/g')
openssl req -new -newkey rsa:2048 -nodes -keyout apiserver-shared.key -subj "/CN=kube-apiserver" -out apiserver-shared.csr 2>/dev/null
openssl x509 -req -in apiserver-shared.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 -out apiserver-shared.crt \
  -extfile <(printf 'keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth,clientAuth\nsubjectAltName=%s\n' "$SAN") 2>/dev/null
openssl x509 -in apiserver-shared.crt -noout -subject -ext extendedKeyUsage
# the kubelet authorizes the client cert user "kube-apiserver" via SubjectAccessReview -> it needs nodes/proxy etc.
kubectl create clusterrolebinding lab:apiserver-shared-kubelet-client --clusterrole=system:kubelet-api-admin --user=kube-apiserver \
  --dry-run=client -o yaml | kubectl apply -f -
sed -i 's|--tls-cert-file=.*|--tls-cert-file=/etc/kubernetes/pki/apiserver-shared.crt|
        s|--tls-private-key-file=.*|--tls-private-key-file=/etc/kubernetes/pki/apiserver-shared.key|
        s|--kubelet-client-certificate=.*|--kubelet-client-certificate=/etc/kubernetes/pki/apiserver-shared.crt|
        s|--kubelet-client-key=.*|--kubelet-client-key=/etc/kubernetes/pki/apiserver-shared.key|' $MAN
wait_api
grep -E 'tls-cert-file|kubelet-client' $MAN
kubectl -n kube-system logs "$(kubectl -n kube-system get pod -l component=etcd -o name | head -1)" --tail=1 | cut -c1-100
