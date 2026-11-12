#!/usr/bin/env bash
# Issue a client cert for "carol" (group carol-team), delete the CSR, delete carol's RBAC... the CERT still authenticates.
set -euo pipefail
cd "$(dirname "$0")"; mkdir -p generated
openssl req -new -newkey rsa:2048 -nodes -keyout generated/carol.key -subj "/CN=carol/O=carol-team" -out generated/carol.csr 2>/dev/null
cat <<Y | kubectl apply -f - >/dev/null
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata: {name: carol}
spec: {request: "$(base64 -w0 generated/carol.csr)", signerName: kubernetes.io/kube-apiserver-client, usages: ["client auth"], expirationSeconds: 3600}
Y
kubectl certificate approve carol >/dev/null
until kubectl get csr carol -o jsonpath='{.status.certificate}' | grep -q .; do sleep 1; done
kubectl get csr carol -o jsonpath='{.status.certificate}' | base64 -d > generated/carol.crt
SERVER=$(kubectl config view --context minikube --minify -o jsonpath='{.clusters[0].cluster.server}')
kubectl config view --context minikube --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > generated/ca.crt
C(){ KUBECONFIG=/dev/null kubectl --server=$SERVER --certificate-authority=generated/ca.crt --client-certificate=generated/carol.crt --client-key=generated/carol.key "$@"; }
echo "1) carol's cert:"; C auth whoami | grep -E 'Username|Groups'
kubectl delete csr carol >/dev/null; echo "2) CSR deleted ->"; C auth whoami | grep Username
echo "3) cert expiry: $(openssl x509 -in generated/carol.crt -noout -enddate)"
