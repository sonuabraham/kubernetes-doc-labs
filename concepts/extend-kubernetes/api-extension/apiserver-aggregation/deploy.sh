#!/usr/bin/env bash
# Creates namespace agg-demo, a CA + serving cert for toy-apiserver.agg-demo.svc, copies the cluster's
# requestheader (front-proxy) CA, deploys the server and registers the APIService.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d)
kubectl create ns agg-demo --dry-run=client -o yaml | kubectl apply -f - >/dev/null
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=toy-apiserver-ca" -keyout $T/ca.key -out $T/ca.crt 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=toy-apiserver.agg-demo.svc" -keyout $T/tls.key -out $T/tls.csr 2>/dev/null
printf 'subjectAltName=DNS:toy-apiserver.agg-demo.svc,DNS:toy-apiserver.agg-demo.svc.cluster.local\n' > $T/ext
openssl x509 -req -in $T/tls.csr -CA $T/ca.crt -CAkey $T/ca.key -CAcreateserial -days 30 -extfile $T/ext -out $T/tls.crt 2>/dev/null
kubectl create secret tls toy-tls -n agg-demo --cert=$T/tls.crt --key=$T/tls.key --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl get cm extension-apiserver-authentication -n kube-system -o jsonpath='{.data.requestheader-client-ca-file}' | cat > $T/rh.crt
kubectl create cm requestheader -n agg-demo --from-file=requestheader-client-ca-file=$T/rh.crt --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create cm toy-apiserver-code -n agg-demo --from-file=$D/toy_apiserver.py --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f $D/00-toy-apiserver.yaml
kubectl rollout status deploy/toy-apiserver -n agg-demo --timeout=120s
sed "s|CA_BUNDLE|$(base64 -w0 $T/ca.crt)|" $D/01-apiservice.yaml | kubectl apply -f -
rm -rf $T
