#!/usr/bin/env bash
# Run the freshly built fakecloud-ccm on the host against the ccmdev-lab cluster (out of cluster, admin kubeconfig).
#   ./run-ccm.sh start | stop        log: fakecloud-ccm/bin/ccm.log
# In production it runs in the cluster (Deployment/DaemonSet on control-plane nodes) with its own ServiceAccount.
cd "$(dirname "$0")" || exit 1
B=fakecloud-ccm/bin; PIDF=$B/ccm.pid
if [ "$1" = stop ]; then
  [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null; echo stopped; exit 0
fi
$B/fakecloud-ccm \
  --cloud-provider=fakecloud \
  --cloud-config=cloud-config.json \
  --kubeconfig=$B/kubeconfig \
  --authentication-kubeconfig=$B/kubeconfig \
  --authorization-kubeconfig=$B/kubeconfig \
  --controllers=cloud-node,cloud-node-lifecycle,service \
  --leader-elect=false \
  --use-service-account-credentials=false \
  --node-monitor-period=10s \
  --bind-address=127.0.0.1 --secure-port=10358 \
  --v=2 > $B/ccm.log 2>&1 &
echo $! > "$PIDF"; disown
echo "fakecloud-ccm started (pid $(cat "$PIDF")), log: $B/ccm.log"
