#!/usr/bin/env bash
kubectl delete namespace imp-cfg --ignore-not-found
rm -f "$(dirname "$0")"/deployment_cmd-made.yaml
