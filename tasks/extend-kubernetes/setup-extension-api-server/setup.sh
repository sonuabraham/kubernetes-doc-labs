#!/usr/bin/env bash
# NOT from the docs: steps 1-15 of "Set up an extension api-server", in order, for extension-apiserver.yaml.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf $T' EXIT
echo "## 1. APIService API enabled?";   kubectl api-resources --api-group=apiregistration.k8s.io --no-headers
echo "## 2. may I create APIServices?"; kubectl auth can-i create apiservices.apiregistration.k8s.io
echo "## 4-5. CA and serving cert (CN = wardle-apiserver.wardle.svc)"
SVC=wardle-apiserver.wardle.svc
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=wardle-ca" -keyout $T/ca.key -out $T/ca.crt 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=$SVC" -keyout $T/tls.key -out $T/tls.csr 2>/dev/null
printf 'subjectAltName=DNS:%s\n' "$SVC" > $T/ext
openssl x509 -req -in $T/tls.csr -CA $T/ca.crt -CAkey $T/ca.key -CAcreateserial -days 30 -extfile $T/ext -out $T/tls.crt 2>/dev/null
echo "## 3, 6-14. namespace, secret, deployment, service account, RBAC, APIService"
kubectl create namespace wardle --dry-run=client -o yaml | kubectl apply -f -
kubectl -n wardle create secret tls wardle-serving-cert --cert=$T/tls.crt --key=$T/tls.key --dry-run=client -o yaml | kubectl apply -f -
sed "s|CA_BUNDLE|$(base64 -w0 $T/ca.crt)|" "$D/extension-apiserver.yaml" | kubectl apply -f -
kubectl -n wardle rollout status deploy/wardle-apiserver --timeout=180s
kubectl wait --for=condition=Available apiservice/v1alpha1.wardle.example.com --timeout=60s
echo "## 15. get the resource"; kubectl get flunders
