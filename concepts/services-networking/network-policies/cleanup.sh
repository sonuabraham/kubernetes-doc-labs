#!/usr/bin/env bash
# Remove all policies (keep the app) or everything.
# Usage: ./cleanup.sh policies   -> delete all NetworkPolicies in np-demo
#        ./cleanup.sh all        -> delete both demo namespaces
case "$1" in
  policies) kubectl delete networkpolicy --all -n np-demo ;;
  all)      kubectl delete namespace np-demo other ;;
  *)        echo "usage: $0 policies|all"; exit 1 ;;
esac
