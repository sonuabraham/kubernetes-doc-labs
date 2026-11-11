#!/usr/bin/env bash
# Run grpcurl from the grpc-client pod against the Gateway's Envoy Service.
# Usage: ./grpc.sh <host> list                         (uses server reflection)
#        ./grpc.sh <host> grpcbin.GRPCBin/Index
#        PROTO=1 ./grpc.sh <host> com.example/Login    (uses /protos/login.proto, no reflection)
# -authority sets the HTTP/2 :authority (= Host) that GRPCRoute hostnames match.
GW=${GATEWAY:-example-gateway}; NS=${GATEWAY_NS:-example-namespace}
HOST=${1:?usage: $0 <host> <list|describe|Service/Method>}; shift
SVC=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=$GW,gateway.envoyproxy.io/owning-gateway-namespace=$NS \
  -o jsonpath='{.items[0].metadata.name}')
[ -z "$SVC" ] && { echo "no Envoy Service for gateway $NS/$GW"; exit 1; }
opts=(-plaintext -authority "$HOST")
[ -n "$PROTO" ] && opts+=(-import-path /protos -proto login.proto -d '{"user":"demo"}')
kubectl exec -n "$NS" grpc-client -- grpcurl "${opts[@]}" "$SVC.envoy-gateway-system:80" "$@"
