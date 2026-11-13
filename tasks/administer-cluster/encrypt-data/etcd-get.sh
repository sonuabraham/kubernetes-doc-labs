#!/usr/bin/env bash
# ./etcd-get.sh /registry/secrets/default/secret1 [bytes]   - read the RAW value the API server stored in etcd
# (bypassing the API server, like an attacker with an etcd backup would) and show the first bytes like hexdump -C.
# Runs etcdctl inside the etcd static Pod on the node.                           (P=<profile>, default encrypt-lab)
P=${P:-encrypt-lab}; KEY=$1; N=${2:-160}
minikube ssh -p "$P" -- "sudo bash -c 'crictl exec \$(crictl ps -q --name etcd) etcdctl \
  --endpoints=https://127.0.0.1:2379 --cacert=/var/lib/minikube/certs/etcd/ca.crt \
  --cert=/var/lib/minikube/certs/etcd/server.crt --key=/var/lib/minikube/certs/etcd/server.key \
  get $KEY --print-value-only | head -c $N | od -A x -t x1z -v'"
