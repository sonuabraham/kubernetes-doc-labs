#!/usr/bin/env bash
# ./run-ccm.sh start <config.yaml> | stop      - the "version N+1" cloud-controller-manager: the fakecloud CCM built in
# ../developing-cloud-controller-manager, run out of cluster against lm-lab with leader election (default on) and
# Leader Migration enabled. Log: ccm.log (gitignored)
cd "$(dirname "$0")" || exit 1
B=../developing-cloud-controller-manager/fakecloud-ccm/bin; PIDF=.ccm.pid
if [ "$1" = stop ]; then [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null; echo stopped; exit 0; fi
kubectl config view --minify --flatten --context lm-lab | cat > $B/kubeconfig-lm
$B/fakecloud-ccm \
  --cloud-provider=fakecloud --cloud-config=cloud-config.json \
  --kubeconfig=$B/kubeconfig-lm --authentication-kubeconfig=$B/kubeconfig-lm --authorization-kubeconfig=$B/kubeconfig-lm \
  --controllers=cloud-node,cloud-node-lifecycle,service \
  --enable-leader-migration ${2:+--leader-migration-config="$2"} \
  --use-service-account-credentials=false --bind-address=127.0.0.1 --secure-port=10359 --v=2 > ccm.log 2>&1 &
echo $! > "$PIDF"; disown; echo "CCM started (pid $(cat "$PIDF")) with $2"
