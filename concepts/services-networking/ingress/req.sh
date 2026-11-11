#!/usr/bin/env bash
# Send HTTP(S) requests to the Ingress controller with a chosen Host header.
# Usage: ./req.sh <host> <path>...         e.g. ./req.sh foo.bar.com /foo /bar
#        ./req.sh -  <path>...             no hostname, request the IP directly
#        SCHEME=https ./req.sh https-example.foo.com /
# Controller address: $INGRESS_IP, or `minikube ip` if not set.
IP=${INGRESS_IP:-$(minikube ip)}
SCHEME=${SCHEME:-http}
PORT=$([ "$SCHEME" = https ] && echo 443 || echo 80)
HOST=${1:?usage: $0 <host|-> <path>...}; shift
for path in "${@:-/}"; do
  if [ "$HOST" = "-" ]; then
    url="$SCHEME://$IP$path"; resolve=()
  else
    url="$SCHEME://$HOST$path"; resolve=(--resolve "$HOST:$PORT:$IP")
  fi
  body=$(curl -sk -m 3 "${resolve[@]}" -w '\n%{http_code}' "$url")
  code=${body##*$'\n'}; body=${body%$'\n'*}
  if [ "$code" = 200 ]; then out="$body"; else out="HTTP $code"; fi
  printf "  %-26s %-16s -> %s\n" "$HOST" "$path" "$out"
done
