#!/usr/bin/env bash
# Creates a real x509 user "bob" (group "caribou-devs") through the CertificateSigningRequest API
# and a kubeconfig generated/bob.kubeconfig for him. Nothing touches ~/.kube/config.
set -euo pipefail
cd "$(dirname "$0")"; mkdir -p generated
openssl req -new -newkey rsa:2048 -nodes -keyout generated/bob.key -subj "/CN=bob/O=caribou-devs" -out generated/bob.csr 2>/dev/null
kubectl delete csr bob --ignore-not-found >/dev/null
cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata: {name: bob}
spec:
  request: $(base64 -w0 generated/bob.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: ["client auth"]
YAML
kubectl certificate approve bob >/dev/null
until kubectl get csr bob -o jsonpath='{.status.certificate}' | grep -q .; do sleep 1; done
kubectl get csr bob -o jsonpath='{.status.certificate}' | base64 -d > generated/bob.crt
SERVER=$(kubectl config view --context minikube --minify -o jsonpath='{.clusters[0].cluster.server}')
kubectl config view --context minikube --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > generated/ca.crt
K=generated/bob.kubeconfig; rm -f $K
kubectl config --kubeconfig=$K set-cluster lab --server=$SERVER --certificate-authority=generated/ca.crt --embed-certs >/dev/null
kubectl config --kubeconfig=$K set-credentials bob --client-certificate=generated/bob.crt --client-key=generated/bob.key --embed-certs >/dev/null
kubectl config --kubeconfig=$K set-context bob --cluster=lab --user=bob --namespace=projectcaribou >/dev/null
kubectl config --kubeconfig=$K use-context bob >/dev/null
openssl x509 -in generated/bob.crt -noout -subject -issuer -enddate
