#!/usr/bin/env bash
# NOT from the docs: give minikube a (fake) cloud load balancer. Runs ONLY the "service" controller of the fakecloud
# cloud-controller-manager built in ../../administer-cluster/developing-cloud-controller-manager against the current
# minikube cluster. It hands out IPs 203.0.113.x (TEST-NET-3, not routable) and adds the LB cleanup finalizer.
#   ./run-fake-lb.sh start | stop          log: ./ccm.log
cd "$(dirname "$0")" || exit 1
CCM=../../administer-cluster/developing-cloud-controller-manager
BIN=$CCM/fakecloud-ccm/bin/fakecloud-ccm
if [ "$1" = stop ]; then [ -f ccm.pid ] && kill "$(cat ccm.pid)" 2>/dev/null; rm -f ccm.pid; echo stopped; exit 0; fi
[ -x "$BIN" ] || { echo "build $BIN first (see $CCM/README.md)"; exit 1; }
kubectl config view --minify --flatten --context minikube | cat > kubeconfig.minikube
$BIN --cloud-provider=fakecloud --cloud-config=$CCM/cloud-config.json \
  --kubeconfig=kubeconfig.minikube --authentication-kubeconfig=kubeconfig.minikube --authorization-kubeconfig=kubeconfig.minikube \
  --controllers=service --leader-elect=false --use-service-account-credentials=false \
  --bind-address=127.0.0.1 --secure-port=10358 --v=2 > ccm.log 2>&1 &
echo $! > ccm.pid; disown
echo "fake LB controller started (pid $(cat ccm.pid)), log: ccm.log"
