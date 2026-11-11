#!/usr/bin/env bash
# Usage: ./cleanup.sh routes  -> delete all HTTPRoutes/GRPCRoutes + lab extras (keep Gateway + app)
#        ./cleanup.sh all     -> delete the demo namespaces and the lab GatewayClasses
#        ./cleanup.sh envoy   -> also uninstall Envoy Gateway (and the Gateway API CRDs it installed)
EG_VERSION=${EG_VERSION:-v1.10.0}
case "$1" in
  routes) kubectl delete httproute,grpcroute --all -n example-namespace
          kubectl delete referencegrant --all -n example-namespace
          kubectl delete namespace team-a --ignore-not-found ;;
  all)    kubectl delete namespace example-namespace team-a --ignore-not-found
          kubectl delete gatewayclass example-class --ignore-not-found ;;
  envoy)  "$0" all
          kubectl delete -f "https://github.com/envoyproxy/gateway/releases/download/$EG_VERSION/install.yaml" --ignore-not-found ;;
  *)      echo "usage: $0 routes|all|envoy"; exit 1 ;;
esac
