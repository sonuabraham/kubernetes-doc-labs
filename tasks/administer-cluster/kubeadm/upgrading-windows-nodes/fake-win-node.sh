#!/usr/bin/env bash
# One API-only "Windows Server 2022" Node, win-node, kept Ready by a heartbeat loop that plays its kubelet.
# minikube can't run Windows; this gives drain/uncordon and the version column something real to act on.
#   ./fake-win-node.sh up v1.36.0     create the Node + start the "kubelet" reporting v1.36.0
#   ./fake-win-node.sh kubelet v1.37.0  "replace kubelet.exe and restart-service kubelet": report a new version
#   ./fake-win-node.sh down           stop the heartbeat, delete the Node
# Pods bound to it never really start or stop (no kubelet), so the lab keeps workloads off it.
set -euo pipefail
cd "$(dirname "$0")"; CTX=${CTX:-kubeadm-lab}; PIDF=.fake-windows-$CTX.pid; VERF=.win-kubelet-version
k(){ command kubectl --context "$CTX" "$@"; }
stop(){ [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null; rm -f "$PIDF"; }
case ${1:-up} in
down) stop; rm -f $VERF; k delete node win-node --ignore-not-found; exit 0 ;;
kubelet) echo "${2:?version}" > $VERF; echo "kubelet on win-node now reports ${2}"; sleep 12; exit 0 ;;
up) echo "${2:-v1.36.0}" > $VERF ;;
esac
k apply -f - >/dev/null <<Y
apiVersion: v1
kind: Node
metadata:
  name: win-node
  labels: {kubernetes.io/hostname: win-node, kubernetes.io/os: windows, kubernetes.io/arch: amd64, node.kubernetes.io/windows-build: "10.0.20348"}
Y
beat(){ while true; do
  now=$(date -u +%FT%TZ); v=$(cat $VERF 2>/dev/null || echo v1.36.0)
  k patch node win-node --subresource=status --type=merge -p "{\"status\":{
    \"capacity\":{\"cpu\":\"4\",\"memory\":\"8Gi\",\"pods\":\"110\"},\"allocatable\":{\"cpu\":\"4\",\"memory\":\"8Gi\",\"pods\":\"110\"},
    \"nodeInfo\":{\"operatingSystem\":\"windows\",\"architecture\":\"amd64\",\"osImage\":\"Windows Server 2022 Datacenter (fake)\",\"kernelVersion\":\"10.0.20348.1\",
                  \"containerRuntimeVersion\":\"containerd://2.1.4\",\"kubeletVersion\":\"$v\",\"machineID\":\"\",\"systemUUID\":\"\",\"bootID\":\"\",\"kubeProxyVersion\":\"\"},
    \"conditions\":[{\"type\":\"Ready\",\"status\":\"True\",\"reason\":\"FakeKubelet\",\"message\":\"fake heartbeat\",\"lastHeartbeatTime\":\"$now\",\"lastTransitionTime\":\"2026-01-01T00:00:00Z\"}]}}" >/dev/null 2>&1
  sleep 10; done; }
stop; beat >/dev/null 2>&1 & echo $! > "$PIDF"; disown
sleep 3; k get nodes -L kubernetes.io/os
