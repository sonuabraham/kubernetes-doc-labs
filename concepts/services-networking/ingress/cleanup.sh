#!/usr/bin/env bash
# Usage: ./cleanup.sh ingresses -> delete all Ingresses in ingress-demo (keep app)
#        ./cleanup.sh all       -> also delete the namespace and lab IngressClasses
case "$1" in
  ingresses) kubectl delete ingress --all -n ingress-demo ;;
  all)       kubectl delete namespace ingress-demo
             kubectl delete ingressclass example-class external-lb-1 external-lb-2 --ignore-not-found ;;
  *)         echo "usage: $0 ingresses|all"; exit 1 ;;
esac
