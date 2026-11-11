#!/usr/bin/env bash
# Send HTTP(S) requests through the Gateway with a chosen Host header.
# Usage: ./req.sh <host> <path>...            ./req.sh www.example.com /login /x
#   H='env: canary' ./req.sh <host> <path>    add a request header
#   X=DELETE        ./req.sh <host> <path>    use another HTTP method
#   SCHEME=https    ./req.sh <host> <path>    HTTPS (SNI = host)
#   RAW=1           ./req.sh <host> <path>    print status line, response headers, full JSON
# Prints: <backend deployment>  (path the backend saw)   or  HTTP <code> [-> redirect]
#
# Gateway address: $GATEWAY_IP (and optional $GATEWAY_PORT), e.g. after `minikube tunnel`;
# otherwise `minikube ip` + the NodePort of the Envoy Service created for the Gateway.
GW=${GATEWAY:-example-gateway}; NS=${GATEWAY_NS:-example-namespace}
SCHEME=${SCHEME:-http}
PORT=$([ "$SCHEME" = https ] && echo 443 || echo 80)
if [ -n "$GATEWAY_IP" ]; then
  IP=$GATEWAY_IP; TPORT=${GATEWAY_PORT:-$PORT}
else
  IP=$(minikube ip)
  TPORT=$(kubectl get svc -n envoy-gateway-system \
    -l gateway.envoyproxy.io/owning-gateway-name=$GW,gateway.envoyproxy.io/owning-gateway-namespace=$NS \
    -o jsonpath="{.items[0].spec.ports[?(@.port==$PORT)].nodePort}" 2>/dev/null)
  [ -z "$TPORT" ] && { echo "Gateway $NS/$GW has no Envoy Service exposing port $PORT (yet)"; exit 1; }
fi
HOST=${1:?usage: $0 <host> <path>...}; shift
hdr=(); [ -n "$H" ] && hdr=(-H "$H")
for path in "${@:-/}"; do
  args=(-sk -m 5 -X "${X:-GET}" "${hdr[@]}" --connect-to "$HOST:$PORT:$IP:$TPORT" "$SCHEME://$HOST$path")
  if [ -n "$RAW" ]; then curl -i "${args[@]}"; echo; continue; fi
  resp=$(curl "${args[@]}" -w $'\n%{http_code} %{redirect_url}')
  meta=${resp##*$'\n'}; body=${resp%$'\n'*}
  code=${meta%% *}; loc=${meta#* }
  case "$code" in
    200) pod=$(jq -r '.pod // empty' <<<"$body" 2>/dev/null)
         seen=$(jq -r '.path // empty' <<<"$body" 2>/dev/null)
         if [ -n "$pod" ]; then out="${pod%-*-*}  (backend saw $seen)"; else out="$body"; fi ;;
    3??) out="HTTP $code -> $loc" ;;
    000) out="no response (timeout / connection refused)" ;;
    *)   out="HTTP $code" ;;
  esac
  printf "  %-24s %-6s %-18s -> %s\n" "$HOST" "${X:-GET}" "$path" "$out"
done
