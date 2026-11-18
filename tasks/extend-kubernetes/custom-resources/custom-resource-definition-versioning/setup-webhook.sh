#!/usr/bin/env bash
# NOT from the docs: create a CA + serving cert for example-conversion-webhook-server.default.svc, deploy the webhook,
# then apply the docs' 04-my-versioned-crontab-with-conversion.yaml with its caBundle placeholder replaced.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf $T' EXIT
SVC=example-conversion-webhook-server.default.svc
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=conversion-webhook-ca" -keyout $T/ca.key -out $T/ca.crt 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=$SVC" -keyout $T/tls.key -out $T/tls.csr 2>/dev/null
printf 'subjectAltName=DNS:%s\n' "$SVC" > $T/ext
openssl x509 -req -in $T/tls.csr -CA $T/ca.crt -CAkey $T/ca.key -CAcreateserial -days 30 -extfile $T/ext -out $T/tls.crt 2>/dev/null
kubectl create secret tls conversion-webhook-tls --cert=$T/tls.crt --key=$T/tls.key --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap conversion-webhook-code --from-file="$D/conversion_webhook.py" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$D/webhook-deployment.yaml"
kubectl rollout status deploy/example-conversion-webhook-server --timeout=120s
sed "s|Ci0tLS0tQk...<base64-encoded PEM bundle>...tLS0K|$(base64 -w0 $T/ca.crt)|" "$D/04-my-versioned-crontab-with-conversion.yaml" | kubectl apply -f -
kubectl wait --for=condition=Established crd/crontabs.example.com
