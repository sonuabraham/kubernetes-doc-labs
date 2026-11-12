#!/usr/bin/env bash
# Runs kubectl authenticated ONLY as the attacker ServiceAccount (its own token, no admin client cert).
# (--as=... on your admin kubeconfig would make YOU do the impersonating, which proves nothing.)
SERVER=$(kubectl config view --context minikube --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(mktemp); kubectl config view --context minikube --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "$CA"
TOKEN=$(kubectl --context minikube create token attacker -n rbac-demo --duration=10m)
KUBECONFIG=/dev/null kubectl --server="$SERVER" --certificate-authority="$CA" --token="$TOKEN" "$@"; rc=$?
rm -f "$CA"; exit $rc
