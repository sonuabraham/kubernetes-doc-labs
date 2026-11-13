#!/usr/bin/env bash
# The docs' "Without kubectl proxy" commands, verbatim, with CLUSTER_NAME preset (override: CLUSTER_NAME=x ./token-access.sh).
# Creates Secret default-token (type service-account-token for SA "default") in the CURRENT namespace.
# Check all possible clusters, as your .KUBECONFIG may have multiple contexts:
kubectl config view -o jsonpath='{"Cluster name\tServer\n"}{range .clusters[*]}{.name}{"\t"}{.cluster.server}{"\n"}{end}'

# Select name of cluster you want to interact with from above output:
export CLUSTER_NAME="${CLUSTER_NAME:-minikube}"

# Point to the API server referring the cluster name
APISERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.server}")

# Create a secret to hold a token for the default service account
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: default-token
  annotations:
    kubernetes.io/service-account.name: default
type: kubernetes.io/service-account-token
EOF

# Wait for the token controller to populate the secret with a token:
while ! kubectl describe secret default-token | grep -E '^token' >/dev/null; do
  echo "waiting for token..." >&2
  sleep 1
done

# Get the token value
TOKEN=$(kubectl get secret default-token -o jsonpath='{.data.token}' | base64 --decode)

# Explore the API with TOKEN
curl -X GET $APISERVER/api --header "Authorization: Bearer $TOKEN" --insecure

# --- not in the docs: the same call WITHOUT --insecure (verify the server with the cluster CA), and what this token may do
CA=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.certificate-authority}")
echo; echo "--- with --cacert $CA:"; curl -s $APISERVER/version --header "Authorization: Bearer $TOKEN" --cacert "$CA" | head -4
echo "--- list pods as this ServiceAccount:"; curl -s $APISERVER/api/v1/namespaces/default/pods --header "Authorization: Bearer $TOKEN" --cacert "$CA" | grep -E '"(reason|message)"'
echo "--- token claims:"; echo "$TOKEN" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | python3 -m json.tool | grep -E '"(iss|sub)"|service-account'
