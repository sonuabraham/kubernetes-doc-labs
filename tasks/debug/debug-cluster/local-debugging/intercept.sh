#!/usr/bin/env bash
# NOT from the docs: a do-it-yourself "telepresence intercept" for minikube (docker driver).
#   ./intercept.sh on  [local-port]  - route ALL traffic of Service tp-demo/hello to <host>:<local-port>
#   ./intercept.sh off               - give the Service back to its Pods
# How: drop the Service selector, clean up the controllers' leftovers (see below) and add a manual
# EndpointSlice whose only endpoint is this machine on the minikube docker network (192.168.58.1).
# Telepresence does the same job with a traffic-agent sidecar + a tunnel, and can intercept only some requests.
set -euo pipefail
NS=tp-demo; HOST_IP=$(minikube ip | sed 's/\.[0-9]*$/.1/'); PORT=${2:-18765}
case ${1:-on} in
on)
  kubectl -n $NS patch svc hello --type=json -p '[{"op":"remove","path":"/spec/selector"}]'
  # Without a selector the controllers stop UPDATING, but leave things behind (measured on 1.37):
  #  - the endpointslice-controller's slice is not deleted
  #  - the legacy Endpoints object stays, and the endpointslice-mirroring controller copies it into a new slice
  # Remove both, or traffic is split between the Pods and the laptop.
  kubectl -n $NS delete endpoints hello --ignore-not-found
  kubectl -n $NS delete endpointslices -l kubernetes.io/service-name=hello,endpointslice.kubernetes.io/managed-by=endpointslice-controller.k8s.io
  sleep 2
  kubectl -n $NS delete endpointslices -l kubernetes.io/service-name=hello,endpointslice.kubernetes.io/managed-by=endpointslicemirroring-controller.k8s.io
  kubectl -n $NS apply -f - <<Y
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: hello-intercept
  namespace: $NS
  labels: {kubernetes.io/service-name: hello, intercept: "true"}
addressType: IPv4
ports: [{name: http, port: $PORT, protocol: TCP}]
endpoints: [{addresses: ["$HOST_IP"], conditions: {ready: true}}]
Y
  ;;
off)
  kubectl -n $NS delete endpointslice hello-intercept --ignore-not-found
  kubectl -n $NS patch svc hello -p '{"spec":{"selector":{"app":"hello"}}}' ;;
esac
kubectl -n $NS get endpointslices -l kubernetes.io/service-name=hello
