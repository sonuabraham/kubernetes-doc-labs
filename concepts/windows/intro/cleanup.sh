#!/usr/bin/env bash
# Delete the lab namespace (force: some Pods sit on fake nodes) and the fake Windows nodes.
D=$(cd "$(dirname "$0")" && pwd)
kubectl delete deploy win-noselector -n win-intro --ignore-not-found >/dev/null 2>&1
"$D/../../scheduling-eviction/delete-ns.sh" win-intro
"$D/../fake-windows-nodes.sh" down
