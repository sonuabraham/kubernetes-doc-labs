#!/usr/bin/env bash
# Delete win-guide (force: Pods on fake nodes), the RuntimeClasses, and the fake Windows nodes.
D=$(cd "$(dirname "$0")" && pwd)
kubectl delete runtimeclass windows-2019 placeholder-handler --ignore-not-found
"$D/../../scheduling-eviction/delete-ns.sh" win-guide
"$D/../fake-windows-nodes.sh" down
