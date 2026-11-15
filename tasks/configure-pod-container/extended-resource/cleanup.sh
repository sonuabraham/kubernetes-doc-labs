#!/usr/bin/env bash
# Remove the Pods, the DRA DeviceClass + lab driver, and the node's dongle advertisement.
cd "$(dirname "$0")"
kubectl delete pod extended-resource-demo extended-resource-demo-2 dra-extended-resource-demo dra-extended-resource-demo-2 --ignore-not-found --now
kubectl delete -f dra-deviceclass.yaml --ignore-not-found
P=minikube ../assign-resources/driver.sh stop driver.example.com 2>/dev/null
kubectl delete resourceslices --field-selector spec.driver=driver.example.com --ignore-not-found
kubectl proxy --port=8001 >/dev/null & PROXY=$!; sleep 2
curl -s --header "Content-Type: application/json-patch+json" --request PATCH \
  --data '[{"op": "remove", "path": "/status/capacity/example.com~1dongle"}]' \
  http://localhost:8001/api/v1/nodes/minikube/status | jq -c .status.capacity
kill $PROXY
