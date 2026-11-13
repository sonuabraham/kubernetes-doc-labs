#!/usr/bin/env bash
# ./kek-audit.sh   - for every Secret in etcd on kms-lab, show which KEK (key_id, stored in clear inside the KMS v2
# envelope next to the wrapped DEK) protects it. Read-only.
P=${P:-kms-lab}
minikube ssh -p "$P" -- "sudo bash -c '
E=\"crictl exec \$(crictl ps -q --name etcd) etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/var/lib/minikube/certs/etcd/ca.crt --cert=/var/lib/minikube/certs/etcd/server.crt --key=/var/lib/minikube/certs/etcd/server.key\"
for k in \$(\$E get /registry/secrets --prefix --keys-only); do
  printf \"%-48s %s\n\" \$k \"\$(\$E get \$k --print-value-only | tr -c \"[:print:]\" \" \" | grep -oE \"kek-[0-9]+\" | head -1)\"
done'"
