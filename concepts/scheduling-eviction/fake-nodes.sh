#!/usr/bin/env bash
# fake-nodes.sh up|down [N]
# Creates N fake Nodes (API objects only, no kubelet) and keeps them "Ready" with a heartbeat loop, so the
# scheduler can be studied on a multi-node cluster without starting more minikube nodes (the host's
# fs.inotify.max_user_instances=128 can't run more node containers).
#   - Pods the scheduler binds to a fake node stay Pending/ContainerCreating forever (nobody runs them):
#     look at .spec.nodeName / events, not at Running.
#   - Fake nodes carry label type=fake and zones zone-a / zone-b / zone-c round-robin.
#   - A DaemonSet-style controller (kindnet, kube-proxy) will create Pods for them too; they're harmless.
set -euo pipefail
cmd=${1:-up}; N=${2:-3}; DIR=$(cd "$(dirname "$0")" && pwd); PIDF=$DIR/.fake-nodes.pid
if [ "$cmd" = down ]; then
  [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null; rm -f "$PIDF"
  kubectl delete node -l type=fake --ignore-not-found; exit 0
fi
zones=(zone-a zone-b zone-c)
for i in $(seq 1 "$N"); do
  n=fake-$i; z=${zones[$(( (i-1) % 3 ))]}
  kubectl apply -f - >/dev/null <<Y
apiVersion: v1
kind: Node
metadata:
  name: $n
  labels: {type: fake, kubernetes.io/hostname: $n, kubernetes.io/os: linux, kubernetes.io/arch: amd64, topology.kubernetes.io/zone: $z}
Y
done
beat(){ while true; do
  now=$(date -u +%FT%TZ)
  for n in $(kubectl get nodes -l type=fake -o name 2>/dev/null); do
    kubectl patch $n --subresource=status --type=merge -p "{\"status\":{\"capacity\":{\"cpu\":\"4\",\"memory\":\"8Gi\",\"pods\":\"110\"},\"allocatable\":{\"cpu\":\"4\",\"memory\":\"8Gi\",\"pods\":\"110\"},\"conditions\":[{\"type\":\"Ready\",\"status\":\"True\",\"reason\":\"FakeKubelet\",\"message\":\"fake heartbeat\",\"lastHeartbeatTime\":\"$now\",\"lastTransitionTime\":\"2026-01-01T00:00:00Z\"}]}}" >/dev/null 2>&1
  done; sleep 10; done; }
[ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null || true
beat >/dev/null 2>&1 & echo $! > "$PIDF"; disown
sleep 3; kubectl get nodes -L topology.kubernetes.io/zone
