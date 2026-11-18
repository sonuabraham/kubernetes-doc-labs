#!/usr/bin/env bash
# NOT from the docs: pretend the minikube node has GPUs. A device plugin would make the kubelet report this; here the
# extended resource is written into the node status directly (as in the "Advertise Extended Resources for a Node" task).
#   ./gpu-capacity.sh add [N] | remove
R=gpu-vendor.example~1example-gpu      # JSON-Patch escaping of "/"
case "${1:-}" in
add)    kubectl patch node minikube --subresource=status --type=json -p "[{\"op\":\"add\",\"path\":\"/status/capacity/$R\",\"value\":\"${2:-2}\"}]" ;;
remove) kubectl patch node minikube --subresource=status --type=json -p "[{\"op\":\"remove\",\"path\":\"/status/capacity/$R\"}]" ;;
*) echo "usage: $0 add [N] | remove"; exit 1 ;;
esac
