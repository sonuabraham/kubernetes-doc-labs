#!/usr/bin/env bash
# etcd-get.sh <context> <namespace> <secret>  - prints the first bytes of the raw etcd value (what a backup/disk thief sees)
kubectl --context "$1" exec -n kube-system "etcd-$(kubectl --context "$1" get nodes -o jsonpath='{.items[0].metadata.name}')" -- \
  etcdctl --cacert /var/lib/minikube/certs/etcd/ca.crt --cert /var/lib/minikube/certs/etcd/server.crt --key /var/lib/minikube/certs/etcd/server.key \
  get "/registry/secrets/$2/$3" --print-value-only | head -c 120 | tr -c '[:print:]' '.'; echo
