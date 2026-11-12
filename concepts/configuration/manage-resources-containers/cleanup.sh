#!/usr/bin/env bash
kubectl delete namespace res-demo pod-resources-example --ignore-not-found
# remove the advertised extended resource from the node
kubectl patch node minikube --subresource=status --type=json -p '[{"op":"remove","path":"/status/capacity/example.com~1foo"}]' >/dev/null 2>&1
true
