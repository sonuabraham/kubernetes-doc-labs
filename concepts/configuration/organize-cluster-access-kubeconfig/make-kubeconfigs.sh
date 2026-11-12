#!/usr/bin/env bash
# Builds two small kubeconfig files in ./generated from your current minikube credentials, without touching ~/.kube/config:
#   generated/a.yaml : cluster "lab", user "red-user" (client cert; paths given relative to THIS dir, stored relative to the kubeconfig), context "red"  (ns default),     current-context red
#   generated/b.yaml : cluster "lab", user "red-user" (a bogus token!), user "blue-user" (ServiceAccount token),
#                      context "blue" (ns kube-system) + context "dev" (ns kc-demo, blue-user),                      current-context blue
set -euo pipefail
cd "$(dirname "$0")"; mkdir -p generated/certs
CTX=minikube
SERVER=$(kubectl config view --context $CTX --minify -o jsonpath='{.clusters[0].cluster.server}')
kubectl config view --context $CTX --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > generated/certs/ca.crt
kubectl config view --context $CTX --minify --flatten -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d > generated/certs/admin.crt
kubectl config view --context $CTX --minify --flatten -o jsonpath='{.users[0].user.client-key-data}'         | base64 -d > generated/certs/admin.key
# a restricted identity: ServiceAccount "developer" in kc-demo, allowed to manage pods there only
kubectl create namespace kc-demo --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create serviceaccount developer -n kc-demo --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create rolebinding developer-edit -n kc-demo --clusterrole=edit --serviceaccount=kc-demo:developer --dry-run=client -o yaml | kubectl apply -f - >/dev/null
TOKEN=$(kubectl create token developer -n kc-demo --duration=1h)

A=generated/a.yaml; B=generated/b.yaml; rm -f $A $B
kubectl config --kubeconfig=$A set-cluster lab --server="$SERVER" --certificate-authority=generated/certs/ca.crt >/dev/null
kubectl config --kubeconfig=$A set-credentials red-user --client-certificate=generated/certs/admin.crt --client-key=generated/certs/admin.key >/dev/null
kubectl config --kubeconfig=$A set-context red --cluster=lab --user=red-user --namespace=default >/dev/null
kubectl config --kubeconfig=$A use-context red >/dev/null

kubectl config --kubeconfig=$B set-cluster lab --server="https://does-not-exist.example:8443" --insecure-skip-tls-verify=true >/dev/null
kubectl config --kubeconfig=$B set-credentials red-user --token=bogus-token-from-b >/dev/null
kubectl config --kubeconfig=$B set-cluster lab2 --server="$SERVER" --certificate-authority=generated/certs/ca.crt >/dev/null
kubectl config --kubeconfig=$B set-credentials blue-user --token="$TOKEN" >/dev/null
kubectl config --kubeconfig=$B set-context blue --cluster=lab --user=red-user --namespace=kube-system >/dev/null
kubectl config --kubeconfig=$B set-context dev --cluster=lab2 --user=blue-user --namespace=kc-demo >/dev/null
kubectl config --kubeconfig=$B use-context blue >/dev/null
echo "wrote $A and $B"
