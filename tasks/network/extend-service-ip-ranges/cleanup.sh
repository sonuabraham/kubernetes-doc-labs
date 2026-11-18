#!/usr/bin/env bash
# Remove what this lab created on svc-lab; ./svc-lab.sh delete removes the whole profile (and starts the default minikube).
D=$(cd "$(dirname "$0")" && pwd)
for i in $(seq 1 16); do kubectl delete service "test-$i" --ignore-not-found; done
kubectl delete servicecidr newcidr1 allowed-1 allowed-2 --ignore-not-found
kubectl delete -f "$D/vap-servicecidr-default.yaml" -f "$D/vap-servicecidr-deny.yaml" --ignore-not-found
