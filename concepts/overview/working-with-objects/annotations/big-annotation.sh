#!/usr/bin/env bash
# Lab 5: Try a ConfigMap whose annotations total <KiB> kibibytes (server dry run).
# Usage: ./big-annotation.sh 200    -> accepted
#        ./big-annotation.sh 260    -> rejected: annotations total size must be <= 262144 bytes
# Uses "kubectl create" (not apply): client-side apply would also copy everything
# into the last-applied-configuration annotation and double the size.
KIB=${1:?usage: $0 <KiB>}
f=$(mktemp)
{ echo 'apiVersion: v1'; echo 'kind: ConfigMap'; echo 'metadata:'
  echo '  name: big-annotation'; echo '  namespace: annotations-demo'
  echo '  annotations:'; printf '    blob: "'
  head -c $((KIB*1024)) /dev/zero | tr '\0' 'x'; echo '"'; } > "$f"
kubectl create -f "$f" --dry-run=server -o name 2>&1 | cut -c1-200
rm -f "$f"
