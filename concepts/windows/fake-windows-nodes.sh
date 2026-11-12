#!/usr/bin/env bash
# fake-windows-nodes.sh up|down
# Two API-only "Windows" Nodes (no kubelet - minikube can't run Windows) kept Ready by a heartbeat loop:
#   win-2022  kubernetes.io/os=windows  node.kubernetes.io/windows-build=10.0.20348  (Windows Server 2022)
#   win-2025  kubernetes.io/os=windows  node.kubernetes.io/windows-build=10.0.26100  (Windows Server 2025)
# They are UNTAINTED; the labs add `os=windows:NoSchedule` themselves (what --register-with-taints would do).
# Pods bound to them never start or terminate: delete with ../scheduling-eviction/delete-ns.sh <ns>.
set -euo pipefail
cmd=${1:-up}; DIR=$(cd "$(dirname "$0")" && pwd)
CTX=${CTX:-$(kubectl config current-context)}; PIDF=$DIR/.fake-windows-$CTX.pid
k(){ command kubectl --context "$CTX" "$@"; }
if [ "$cmd" = down ]; then
  [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null; rm -f "$PIDF"
  k delete node -l type=fake-windows --ignore-not-found; exit 0
fi
for spec in "win-2022 10.0.20348 2022" "win-2025 10.0.26100 2025"; do
  set -- $spec
  k apply -f - >/dev/null <<Y
apiVersion: v1
kind: Node
metadata:
  name: $1
  labels: {type: fake-windows, kubernetes.io/hostname: $1, kubernetes.io/os: windows, kubernetes.io/arch: amd64, node.kubernetes.io/windows-build: "$2"}
Y
done
beat(){ while true; do
  now=$(date -u +%FT%TZ)
  for spec in "win-2022 10.0.20348 2022" "win-2025 10.0.26100 2025"; do
    set -- $spec
    k patch node "$1" --subresource=status --type=merge -p "{\"status\":{
      \"capacity\":{\"cpu\":\"4\",\"memory\":\"8Gi\",\"pods\":\"110\"},\"allocatable\":{\"cpu\":\"4\",\"memory\":\"8Gi\",\"pods\":\"110\"},
      \"nodeInfo\":{\"operatingSystem\":\"windows\",\"architecture\":\"amd64\",\"osImage\":\"Windows Server $3 Datacenter (fake)\",\"kernelVersion\":\"$2.1\",
                    \"containerRuntimeVersion\":\"containerd://2.1.4\",\"kubeletVersion\":\"v1.37.0\",\"machineID\":\"\",\"systemUUID\":\"\",\"bootID\":\"\",\"kubeProxyVersion\":\"\"},
      \"conditions\":[{\"type\":\"Ready\",\"status\":\"True\",\"reason\":\"FakeKubelet\",\"message\":\"fake heartbeat\",\"lastHeartbeatTime\":\"$now\",\"lastTransitionTime\":\"2026-01-01T00:00:00Z\"}]}}" >/dev/null 2>&1
  done; sleep 10; done; }
[ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null || true
beat >/dev/null 2>&1 & echo $! > "$PIDF"; disown
sleep 3; k get nodes -o wide -L node.kubernetes.io/windows-build
