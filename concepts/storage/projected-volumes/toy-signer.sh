#!/usr/bin/env bash
# A toy signer for the docs' podCertificate example (signerName coolcert.example.com/foo).
# Real signers (cert-manager, SPIFFE/SPIRE, a mesh) do the same job:
#   watch PodCertificateRequests for their signerName -> sign the kubelet's key -> write status.
# Loops every 3s; Ctrl-C to stop. CA material lives in ./.toy-ca (created on first run).
set -uo pipefail
SIGNER=coolcert.example.com/foo
CA=$(dirname "$0")/.toy-ca; mkdir -p "$CA"
[ -f "$CA/ca.pem" ] || openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 \
    -subj "/CN=coolcert toy CA" -keyout "$CA/ca.key" -out "$CA/ca.pem" 2>/dev/null
while true; do
  kubectl get podcertificaterequests -A -o json | jq -r --arg s "$SIGNER" '.items[]
     | select(.spec.signerName==$s and ((.status.conditions // []) | length == 0))
     | [.metadata.namespace, .metadata.name, .spec.podName, .spec.stubPKCS10Request] | @tsv' |
  while IFS=$'\t' read -r ns name pod csr; do
    echo "$csr" | base64 -d > "$CA/req.der"
    openssl x509 -req -inform DER -in "$CA/req.der" -CA "$CA/ca.pem" -CAkey "$CA/ca.key" \
        -subj "/CN=$pod.$ns" -days 1 -out "$CA/leaf.pem" 2>/dev/null || { echo "sign failed for $ns/$name"; continue; }
    nb=$(date -u -d "$(openssl x509 -in "$CA/leaf.pem" -noout -startdate | cut -d= -f2)" +%FT%TZ)
    na=$(date -u -d "$(openssl x509 -in "$CA/leaf.pem" -noout -enddate   | cut -d= -f2)" +%FT%TZ)
    rf=$(date -u -d "$na - 4 hours" +%FT%TZ)          # ask the kubelet to refresh well before expiry
    now=$(date -u +%FT%TZ)
    jq -n --arg chain "$(cat "$CA/leaf.pem")" --arg nb "$nb" --arg na "$na" --arg rf "$rf" --arg now "$now" '{status:{
        certificateChain:$chain, notBefore:$nb, notAfter:$na, beginRefreshAt:$rf,
        conditions:[{type:"Issued",status:"True",reason:"ToySigner",message:"signed by the toy CA",lastTransitionTime:$now}]}}' \
      > "$CA/status.json"
    kubectl patch podcertificaterequest "$name" -n "$ns" --subresource=status --type=merge --patch-file "$CA/status.json" >/dev/null \
      && echo "$(date +%T) issued $ns/$name for pod $pod (valid until $na)"
  done
  sleep 3
done
