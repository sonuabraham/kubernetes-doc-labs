#!/usr/bin/env bash
# Usage: ./cleanup.sh services  -> delete all lab Services (keep the app)
#        ./cleanup.sh all       -> delete the svc-demo namespace
case "$1" in
  services) kubectl delete svc --all -n svc-demo
            kubectl delete endpointslice manual-service-1 -n svc-demo --ignore-not-found ;;
  all)      kubectl delete namespace svc-demo ;;
  *)        echo "usage: $0 services|all"; exit 1 ;;
esac
