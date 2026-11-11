#!/usr/bin/env bash
# Run etcdctl inside the etcd static pod with minikube's client certificates.
# Usage: ./etcdctl.sh get /registry/configmaps/components-demo/demo-config
#        ./etcdctl.sh get /registry/pods --prefix --keys-only
C=/var/lib/minikube/certs/etcd
kubectl exec -n kube-system etcd-minikube -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=$C/ca.crt --cert=$C/server.crt --key=$C/server.key "$@"
