#!/usr/bin/env bash
# Deploys webhook.py as Deployment+Service "lab-webhook" in namespace webhook-system with a self-signed TLS cert
# for lab-webhook.webhook-system.svc, and prints the CA bundle into generated/ca.b64 for the webhook configurations.
set -euo pipefail
cd "$(dirname "$0")"; mkdir -p generated
SVC=lab-webhook.webhook-system.svc
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=$SVC" -addext "subjectAltName=DNS:$SVC" \
  -keyout generated/tls.key -out generated/tls.crt 2>/dev/null
base64 -w0 generated/tls.crt > generated/ca.b64
kubectl create ns webhook-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create secret tls lab-webhook-tls -n webhook-system --cert=generated/tls.crt --key=generated/tls.key --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create configmap lab-webhook-code -n webhook-system --from-file=webhook.py --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f - >/dev/null <<Y
apiVersion: apps/v1
kind: Deployment
metadata: {name: lab-webhook, namespace: webhook-system}
spec:
  replicas: 1
  selector: {matchLabels: {app: lab-webhook}}
  template:
    metadata: {labels: {app: lab-webhook}}
    spec:
      containers:
      - name: hook
        image: python:3.12-alpine
        command: ["python", "/code/webhook.py"]
        ports: [{containerPort: 8443}]
        volumeMounts: [{name: code, mountPath: /code}, {name: tls, mountPath: /tls}]
      volumes:
      - {name: code, configMap: {name: lab-webhook-code}}
      - {name: tls, secret: {secretName: lab-webhook-tls}}
---
apiVersion: v1
kind: Service
metadata: {name: lab-webhook, namespace: webhook-system}
spec: {selector: {app: lab-webhook}, ports: [{port: 443, targetPort: 8443}]}
Y
kubectl rollout status deploy/lab-webhook -n webhook-system --timeout=120s
