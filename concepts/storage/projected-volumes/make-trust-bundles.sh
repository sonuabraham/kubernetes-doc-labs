#!/usr/bin/env bash
# Creates the two ClusterTrustBundles the docs' projected-clustertrustbundle.yaml selects:
#   - "example"                                  (no signer, selected by NAME)
#   - "example.com:mysigner:live-roots"          (signerName example.com/mysigner, label version=live, selected by signer + labels)
# Each holds a freshly generated self-signed CA certificate.
set -euo pipefail
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
gen() { openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 \
          -subj "/CN=$1" -keyout "$tmp/$1.key" -out "$tmp/$1.pem" 2>/dev/null; }
gen example-root ; gen mysigner-root
cat <<YAML | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: ClusterTrustBundle
metadata:
  name: example
spec:
  trustBundle: |
$(sed 's/^/    /' "$tmp/example-root.pem")
---
apiVersion: certificates.k8s.io/v1
kind: ClusterTrustBundle
metadata:
  name: example.com:mysigner:live-roots
  labels:
    version: live
spec:
  signerName: example.com/mysigner
  trustBundle: |
$(sed 's/^/    /' "$tmp/mysigner-root.pem")
YAML
