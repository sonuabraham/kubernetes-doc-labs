#!/usr/bin/env bash
# NOT from the docs: a THROWAWAY profile "svc-lab" whose Service range is the docs' tiny 10.96.0.0/28 (14 usable IPs).
# Also used by ../reconfigure-default-service-ip-ranges.
#   ./svc-lab.sh start | delete
set -euo pipefail
case "${1:-}" in
start)  minikube stop || true
        minikube start -p svc-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 --service-cluster-ip-range=10.96.0.0/28 ;;
delete) minikube delete -p svc-lab; minikube start; kubectl config use-context minikube ;;
*) echo "usage: $0 start|delete"; exit 1 ;;
esac
