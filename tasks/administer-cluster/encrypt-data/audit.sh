#!/usr/bin/env bash
# ./audit.sh [prefix]   - count how the objects under an etcd prefix are stored (default /registry/secrets):
#   k8s:enc:aescbc:v1:<key>  = encrypted with that key     "k8s" + binary = plain protobuf     "{" = plain JSON
P=${P:-encrypt-lab}; PFX=${1:-/registry/secrets}
minikube ssh -p "$P" -- "sudo bash -c '
E=\"crictl exec \$(crictl ps -q --name etcd) etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/var/lib/minikube/certs/etcd/ca.crt --cert=/var/lib/minikube/certs/etcd/server.crt --key=/var/lib/minikube/certs/etcd/server.key\"
for k in \$(\$E get $PFX --prefix --keys-only); do
  v=\$(\$E get \$k --print-value-only | head -c 23 | tr -c \"[:print:]\" \".\")
  echo \"\$v\"
done | sed -E \"s/^k8s\\.\\..*/k8s.. (plain protobuf)/; s/^\\{.*/{ (plain JSON)/\" | sort | uniq -c'"
