#!/usr/bin/env bash
# Delete the demo Pods and remove every advertisement this lab adds (JSON-patch "remove" on node status, like the
# docs' curl - here via kubectl's --subresource=status, no proxy needed). Missing paths are ignored.
N=${1:-minikube}
kubectl delete ns dongle-demo --ignore-not-found
for r in example.com~1dongle example.com~1special-storage; do
  kubectl patch node "$N" --subresource=status --type=json -p "[{\"op\":\"remove\",\"path\":\"/status/capacity/$r\"}]" 2>/dev/null \
    && echo "removed ${r/\~1//}"
done
kubectl describe node "$N" | grep -E "dongle|special-storage" || echo "no dongle/special-storage left"
