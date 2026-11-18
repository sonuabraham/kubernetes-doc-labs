#!/usr/bin/env bash
# NOT from the docs: test the page's "CA Reusage and Conflicts" warning on a THROWAWAY profile agg-lab whose
# kube-apiserver uses the cluster CA for BOTH --client-ca-file and --requestheader-client-ca-file.
#   ./ca-reuse-lab.sh start | probe | delete
# start stops the default minikube profile first (two clusters exhaust inotify on this host).
set -euo pipefail
case "${1:-}" in
start)
  minikube stop || true
  minikube start -p agg-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 \
    --extra-config=apiserver.requestheader-client-ca-file=/var/lib/minikube/certs/ca.crt
  minikube -p agg-lab ssh -- "sudo grep -E 'requestheader-client-ca|client-ca-file' /etc/kubernetes/manifests/kube-apiserver.yaml" ;;
probe)
  P=$HOME/.minikube/profiles/agg-lab; IP=$(minikube -p agg-lab ip); T=$(mktemp -d); trap 'rm -rf $T' EXIT
  SSR='{"apiVersion":"authentication.k8s.io/v1","kind":"SelfSubjectReview"}'
  who() { curl -s "$@" -X POST -H 'Content-Type: application/json' -d "$SSR" \
            https://$IP:8443/apis/authentication.k8s.io/v1/selfsubjectreviews | jq -c '.status.userInfo.username // .message, .status.userInfo.groups'; }
  echo "1) normal client cert (CN=minikube-user):"
  who --cert $P/client.crt --key $P/client.key --cacert ~/.minikube/ca.crt
  echo "2) same cert + X-Remote-User: mallory:"
  who --cert $P/client.crt --key $P/client.key --cacert ~/.minikube/ca.crt -H 'X-Remote-User: mallory'
  # a cert from the CLUSTER CA with the allowed proxy name (lab only: the CA key is read from the node)
  minikube -p agg-lab ssh -- sudo cat /var/lib/minikube/certs/ca.key | cat > $T/ca.key
  openssl req -newkey rsa:2048 -nodes -subj "/CN=front-proxy-client" -keyout $T/fp.key -out $T/fp.csr 2>/dev/null
  openssl x509 -req -in $T/fp.csr -CA ~/.minikube/ca.crt -CAkey $T/ca.key -CAcreateserial -CAserial $T/srl -days 1 -out $T/fp.crt 2>/dev/null
  echo "3) cluster-CA cert CN=front-proxy-client + X-Remote-User: mallory, X-Remote-Group: system:masters:"
  who --cert $T/fp.crt --key $T/fp.key --cacert ~/.minikube/ca.crt -H 'X-Remote-User: mallory' -H 'X-Remote-Group: system:masters'
  echo "4) same cert, no headers:"
  who --cert $T/fp.crt --key $T/fp.key --cacert ~/.minikube/ca.crt ;;
delete)
  minikube delete -p agg-lab; minikube start ;;
*) echo "usage: $0 start|probe|delete"; exit 1 ;;
esac
