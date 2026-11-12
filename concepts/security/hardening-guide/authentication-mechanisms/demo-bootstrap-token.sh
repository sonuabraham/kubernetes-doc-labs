#!/usr/bin/env bash
# A bootstrap token is a credential: user system:bootstrap:<id>, group system:bootstrappers (+ extra groups).
set -euo pipefail
ID=lab123; SECRET=0123456789abcdef
EXP=$(date -u -d '+30 min' +%FT%TZ)
kubectl apply -f - >/dev/null <<Y
apiVersion: v1
kind: Secret
metadata: {name: bootstrap-token-$ID, namespace: kube-system}
type: bootstrap.kubernetes.io/token
stringData: {token-id: $ID, token-secret: $SECRET, expiration: "$EXP", usage-bootstrap-authentication: "true", auth-extra-groups: "system:bootstrappers:lab"}
Y
SERVER=$(kubectl config view --context minikube --minify -o jsonpath='{.clusters[0].cluster.server}')
KUBECONFIG=/dev/null kubectl --server=$SERVER --insecure-skip-tls-verify --token=$ID.$SECRET auth whoami | grep -E 'Username|Groups'
echo "can it create CSRs (to join as a node)? $(kubectl auth can-i create certificatesigningrequests --as=system:bootstrap:$ID --as-group=system:bootstrappers)"
echo "token expires $EXP; the tokencleaner controller deletes it after that"
