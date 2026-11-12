#!/usr/bin/env bash
# ./etcd-get.sh <key>  - read one raw value from etcd on the minikube node (read-only).
minikube ssh -- "sudo crictl exec \$(sudo crictl ps -q --name etcd) etcdctl --cacert /var/lib/minikube/certs/etcd/ca.crt --cert /var/lib/minikube/certs/etcd/server.crt --key /var/lib/minikube/certs/etcd/server.key get --print-value-only $1"
