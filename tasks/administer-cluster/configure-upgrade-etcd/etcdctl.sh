#!/usr/bin/env bash
# ./etcdctl.sh <etcdctl args...>      run etcdctl INSIDE the etcd static Pod of the etcd-lab node, with the TLS flags
#                                     from the docs' "Securing communication" example (minikube's cert paths).
# TOOL=etcdutl ./etcdctl.sh <args>    run etcdutl instead (offline tool: snapshot status/restore, defrag of a data dir).
# The etcd image is distroless (no shell); files it writes must go under its data-dir mount, /var/lib/minikube/etcd.
P=${P:-etcd-lab}; TOOL=${TOOL:-etcdctl}
TLS=""
[ "$TOOL" = etcdctl ] && TLS="--endpoints=https://127.0.0.1:2379 --cacert=/var/lib/minikube/certs/etcd/ca.crt --cert=/var/lib/minikube/certs/etcd/server.crt --key=/var/lib/minikube/certs/etcd/server.key"
minikube ssh -p "$P" -- "sudo crictl exec \$(sudo crictl ps -q --name etcd) $TOOL $TLS $*"
