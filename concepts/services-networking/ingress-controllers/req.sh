#!/usr/bin/env bash
# Usage: ./req.sh <host>   -> request through the toy proxy (from a pod) with that Host header
kubectl run req-$RANDOM -n ingressctl-demo --rm -i --quiet --restart=Never --image=busybox:1.36 -- \
  wget -qO- --header "Host: $1" http://toy-proxy 2>&1 | head -2
