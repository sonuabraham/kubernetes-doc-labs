#!/usr/bin/env bash
# Separate minikube profile "enc-lab" so the main cluster's API server is never touched.
# 1) start plain  2) copy the EncryptionConfiguration into the node's certs dir (already mounted into kube-apiserver)
# 3) restart with --encryption-provider-config pointing at it.
set -euo pipefail
cd "$(dirname "$0")"
minikube start -p enc-lab --memory 2048 --cpus 2 --kubernetes-version v1.37.0
kubectl --context enc-lab create secret generic before-encryption --from-literal=password=plain-old-secret
minikube -p enc-lab cp encryption-config.yaml /var/lib/minikube/certs/encryption-config.yaml
minikube start -p enc-lab --extra-config=apiserver.encryption-provider-config=/var/lib/minikube/certs/encryption-config.yaml
kubectl --context enc-lab get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[]' | grep encryption
echo "When done: minikube stop -p enc-lab (or delete) ; kubectl config use-context minikube"
