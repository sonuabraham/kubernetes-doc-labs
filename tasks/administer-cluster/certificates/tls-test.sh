#!/usr/bin/env bash
# ./tls-test.sh <server.crt> <server.key> <ca.crt>
# Serve the cert with "openssl s_server" on 127.0.0.1:18443 (stand-in for a kube-apiserver started with
# --tls-cert-file/--tls-private-key-file) and connect as two kinds of client, trusting only <ca.crt>:
#   curl    (OpenSSL verifier)  as https://kubernetes.default.svc
#   kubectl (Go verifier)       as https://127.0.0.1  (needs a 127.0.0.1 SAN)
crt=$1 key=$2 ca=$3
openssl s_server -accept 18443 -cert "$crt" -key "$key" -www -quiet >/dev/null 2>&1 & P=$!; sleep 1
echo "curl    https://kubernetes.default.svc: $(curl -sS --cacert "$ca" --resolve kubernetes.default.svc:18443:127.0.0.1 \
  https://kubernetes.default.svc:18443/ -o /dev/null -w '%{http_code}' 2>&1 | head -1)"
echo "kubectl https://127.0.0.1:              $(kubectl --kubeconfig=/dev/null --token x --server https://127.0.0.1:18443 \
  --certificate-authority "$ca" get --raw / 2>&1 | head -1 | sed 's/<HTML>.*/TLS OK (got the test page)/' | cut -c1-150)"
kill $P
