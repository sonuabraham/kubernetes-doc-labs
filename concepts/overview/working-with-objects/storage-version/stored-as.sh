#!/usr/bin/env bash
# Print the apiVersion each crontab is stored as IN ETCD (CRs are stored as JSON).
# Usage: ./stored-as.sh
for k in $(./etcdctl.sh get /registry/example.com/crontabs/storage-version-demo --prefix --keys-only | grep -v '^$'); do
  printf '%-58s %s\n' "$k" "$(./etcdctl.sh get "$k" --print-value-only | jq -r .apiVersion)"
done
