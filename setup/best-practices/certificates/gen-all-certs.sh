#!/usr/bin/env bash
# NOT from the docs – the page's "All certificates" + "Configure certificates for user accounts" tables, done with openssl.
# Every CN / O / kind / SAN comes from the page's tables (the "Default CN" column, not kubeadm's own names).
# Output: /root/pki-out (the "offline" CA side, CA keys included) and /root/pki-out/etc-kubernetes (what goes onto the node:
# NO ca.key, etcd/ca.key, front-proxy-ca.key -> kubeadm "external CA" mode).
# Run as root on the machine that will become the control plane:
#   ../../production-environment/tools/kubeadm/machines.sh x cp2 "HOST_NAME=cp2 HOST_IP=172.30.0.3; $(cat gen-all-certs.sh)"
# EXTRA_APISERVER_SANS="IP:10.96.0.1" adds the Service ClusterIP that the docs' SAN list leaves out (see README, Lab 3).
set -euo pipefail
: "${HOST_NAME:?}" "${HOST_IP:?}"
OUT=/root/pki-out; rm -rf $OUT; mkdir -p $OUT/etcd; cd $OUT
DAYS=365

ca() { # path CN
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.crt" -days 3650 -subj "/CN=$2" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign" 2>/dev/null
}
cert() { # path parentCA subject kind(server|client|server,client) [SANs]
  local eku=; case $4 in server) eku=serverAuth;; client) eku=clientAuth;; server,client) eku=serverAuth,clientAuth;; esac
  openssl req -new -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.csr" -subj "$3" 2>/dev/null
  { echo "keyUsage=critical,digitalSignature,keyEncipherment"; echo "extendedKeyUsage=$eku"; [ -n "${5:-}" ] && echo "subjectAltName=$5"; } > "$1.ext"
  openssl x509 -req -in "$1.csr" -CA "$2.crt" -CAkey "$2.key" -CAcreateserial -days $DAYS -out "$1.crt" -extfile "$1.ext" 2>/dev/null
  rm -f "$1.csr" "$1.ext"
}

# --- Single root CA table: the 3 required CAs
ca ca             kubernetes-ca
ca etcd/ca        etcd-ca
ca front-proxy-ca kubernetes-front-proxy-ca

# --- All certificates table
ETCD_SANS="DNS:$HOST_NAME,IP:$HOST_IP,DNS:localhost,IP:127.0.0.1"
cert etcd/server                 etcd/ca        "/CN=kube-etcd"                    server,client "$ETCD_SANS"
cert etcd/peer                   etcd/ca        "/CN=kube-etcd-peer"               server,client "$ETCD_SANS"
cert etcd/healthcheck-client     etcd/ca        "/CN=kube-etcd-healthcheck-client" client
cert apiserver-etcd-client       etcd/ca        "/CN=kube-apiserver-etcd-client"   client
# footnote [^1]: kubernetes, kubernetes.default, kubernetes.default.svc, kubernetes.default.svc.cluster, kubernetes.default.svc.cluster.local
APISERVER_SANS="DNS:$HOST_NAME,IP:$HOST_IP,DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc,DNS:kubernetes.default.svc.cluster,DNS:kubernetes.default.svc.cluster.local"
[ -n "${EXTRA_APISERVER_SANS:-}" ] && APISERVER_SANS="$APISERVER_SANS,$EXTRA_APISERVER_SANS"
cert apiserver                   ca             "/CN=kube-apiserver"               server "$APISERVER_SANS"
cert apiserver-kubelet-client    ca             "/O=system:masters/CN=kube-apiserver-kubelet-client" client
cert front-proxy-client          front-proxy-ca "/CN=front-proxy-client"           client

# --- service account key pair
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out sa.key 2>/dev/null
openssl pkey -in sa.key -pubout -out sa.pub

# --- user accounts table + the page's 4 kubectl commands per file
mkdir -p users kubeconfigs
user() { # file credential-name subject
  cert "users/$1" ca "$3" client
  local K=kubeconfigs/$1.conf
  KUBECONFIG=$K kubectl config set-cluster default-cluster --server=https://$HOST_IP:6443 --certificate-authority ca.crt --embed-certs
  KUBECONFIG=$K kubectl config set-credentials $2 --client-key users/$1.key --client-certificate users/$1.crt --embed-certs
  KUBECONFIG=$K kubectl config set-context default-system --cluster default-cluster --user $2
  KUBECONFIG=$K kubectl config use-context default-system
}
user admin              default-admin              "/O=kubeadm:cluster-admins/CN=kubernetes-admin"     >/dev/null
user super-admin        default-super-admin        "/O=system:masters/CN=kubernetes-super-admin"       >/dev/null
user kubelet            default-auth               "/O=system:nodes/CN=system:node:$HOST_NAME"         >/dev/null
user controller-manager default-controller-manager "/CN=system:kube-controller-manager"                >/dev/null
user scheduler          default-scheduler          "/CN=system:kube-scheduler"                         >/dev/null

# --- what the node gets: everything except the CA private keys
N=$OUT/etc-kubernetes; mkdir -p $N/pki/etcd
cp ca.crt front-proxy-ca.crt sa.key sa.pub apiserver*.crt apiserver*.key front-proxy-client.* $N/pki/
cp etcd/ca.crt etcd/server.* etcd/peer.* etcd/healthcheck-client.* $N/pki/etcd/
cp kubeconfigs/*.conf $N/
find $N -type f | sort
