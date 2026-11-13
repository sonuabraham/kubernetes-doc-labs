#!/usr/bin/env bash
# ./stop-test.sh [profile]  - create the Pod, show whether the API server kept lifecycle.stopSignal, delete it,
# then print which signal the container received (it writes that to a hostPath file on the node).
P=${1:-fg-lab}; K="kubectl --context $P"
$K delete pod stop-signal-demo --ignore-not-found --wait >/dev/null 2>&1
$K apply -f "$(dirname "$0")/01-stop-signal-pod.yaml" 2>&1 | cat
$K wait --for=condition=Ready pod/stop-signal-demo --timeout=120s >/dev/null
echo "stored lifecycle: $($K get pod stop-signal-demo -o jsonpath='{.spec.containers[0].lifecycle}')"
$K delete pod stop-signal-demo --wait >/dev/null
echo "container received: $(minikube ssh -p $P -- 'tail -1 /tmp/stop-signal/received' | tr -d '\r')"
