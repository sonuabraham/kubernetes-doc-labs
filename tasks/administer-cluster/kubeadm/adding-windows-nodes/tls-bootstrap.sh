#!/usr/bin/env bash
# Replay the TLS BOOTSTRAP + REGISTRATION a joining kubelet does (here for a Windows Server 2022 machine that
# doesn't exist).   ./tls-bootstrap.sh <server-host:port> <token> [node-name]     (run ./discover.py first: needs ca.crt)
# 1. As system:bootstrap:<token-id>, file a CSR for CN=system:node:<name>, O=system:nodes
#    (signer kubernetes.io/kube-apiserver-client-kubelet). kubeadm's RBAC lets the csrapprover auto-approve it.
# 2. Download the signed client cert -> win-node.crt/.key (what the kubelet keeps in /var/lib/kubelet/pki).
# 3. As system:node:<name>, create the Node object with the labels a Windows kubelet sets.
set -euo pipefail
SERVER=$1 TOKEN=$2 NODE=${3:-win-node}
cd "$(dirname "$0")"
kb(){ kubectl --kubeconfig=/dev/null --server "https://$SERVER" --certificate-authority ca.crt --token "$TOKEN" "$@"; }
kn(){ kubectl --kubeconfig=/dev/null --server "https://$SERVER" --certificate-authority ca.crt --client-certificate $NODE.crt --client-key $NODE.key "$@"; }

echo "== who am I with the bootstrap token?"; kb auth whoami
openssl ecparam -name prime256v1 -genkey -noout -out $NODE.key 2>/dev/null
openssl req -new -key $NODE.key -subj "/O=system:nodes/CN=system:node:$NODE" -out $NODE.csr
CSR=node-csr-$NODE-$(date +%s)
kb create -f - <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $CSR
spec:
  request: $(base64 -w0 $NODE.csr)
  signerName: kubernetes.io/kube-apiserver-client-kubelet
  usages: [digital signature, client auth]
EOF
for i in $(seq 30); do
  cert=$(kb get csr $CSR -o jsonpath='{.status.certificate}' 2>/dev/null || true)
  [ -n "$cert" ] && break; sleep 1
done
[ -n "$cert" ] || { echo "CSR not issued"; exit 1; }
echo "$cert" | base64 -d > $NODE.crt
echo "== issued:"; openssl x509 -in $NODE.crt -noout -subject -issuer -enddate

echo "== who am I with the node cert?"; kn auth whoami
kn create -f - <<EOF
apiVersion: v1
kind: Node
metadata:
  name: $NODE
  labels:
    kubernetes.io/hostname: $NODE
    kubernetes.io/os: windows
    kubernetes.io/arch: amd64
    node.kubernetes.io/windows-build: "10.0.20348"
EOF
