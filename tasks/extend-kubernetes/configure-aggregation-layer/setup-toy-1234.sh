#!/usr/bin/env bash
# NOT from the docs: deploy the concept lab's toy extension API server, then move its Service to port 1234 and
# re-register the APIService with port: 1234 and the same caBundle.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
C=$D/../../../concepts/extend-kubernetes/api-extension/apiserver-aggregation
"$C/deploy.sh"
CA=$(kubectl get apiservice v1.toys.example.com -o jsonpath='{.spec.caBundle}')
kubectl -n agg-demo patch svc toy-apiserver --type=json -p='[{"op":"replace","path":"/spec/ports/0/port","value":1234}]'
sed "s|CA_BUNDLE|$CA|" "$D/apiservice-port-1234.yaml" | kubectl apply -f -
