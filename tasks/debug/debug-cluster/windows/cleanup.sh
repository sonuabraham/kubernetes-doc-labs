#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f wrong-os.yaml --ignore-not-found --now
../../../../concepts/windows/fake-windows-nodes.sh down 2>/dev/null
true
