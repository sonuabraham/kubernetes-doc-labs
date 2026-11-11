#!/usr/bin/env bash
# Sends N requests from a client pod to a URL and counts which pod answered.
# Usage: ./test.sh <url> [count] [client-pod]
#   ./test.sh http://my-service/hostname
#   ./test.sh http://my-sticky/hostname 20
#   ./test.sh http://my-local-internal/hostname 20 client
NS=svc-demo
URL=${1:?usage: $0 <url> [count] [client-pod]}
COUNT=${2:-12}
CLIENT=${3:-client}

echo "== $COUNT requests from $NS/$CLIENT to $URL =="
kubectl exec -n "$NS" "$CLIENT" -- sh -c "
  for i in \$(seq $COUNT); do
    curl -s -m 2 '$URL' || echo '<no answer>'
    echo
  done" | grep -v '^$' | sort | uniq -c
