#!/usr/bin/env bash
# NOT from the docs. The page's failure mode "API server VM shutdown or apiserver crashing", on minikube:
# move the kube-apiserver static Pod manifest out of /etc/kubernetes/manifests for ~40 s, show that
#   - kubectl stops working          ("unable to stop, update, or start new pods ...")
#   - the running app keeps serving through its Service  ("existing pods and services should continue to work")
# then move the manifest back and wait for /readyz.
set -u
M=/etc/kubernetes/manifests/kube-apiserver.yaml
IP=$(kubectl get svc web -o jsonpath='{.spec.clusterIP}')
for i in $(seq 1 10); do minikube ssh -- curl -s -m 2 $IP >/dev/null 2>&1 && break; sleep 2; done   # wait for kube-proxy rules
echo "before:   $(minikube ssh -- curl -s -m 3 $IP | tr -d '\r')"
minikube ssh -- "sudo cp $M /root/kube-apiserver.backup.yaml && sudo mv $M /root/kube-apiserver.yaml"
for i in $(seq 1 20); do kubectl get --raw /readyz >/dev/null 2>&1 || break; sleep 2; done
echo "kubectl:  $(kubectl get pods 2>&1 | head -1 | cut -c1-110)"
for i in 1 2 3; do echo "service:  $(minikube ssh -- curl -s -m 3 $IP | tr -d '\r')"; sleep 5; done
echo "on node:  $(minikube ssh -- "sudo crictl pods --label app=web --state ready -q | wc -l" | tr -d '\r') web Pod sandbox(es) still running"
minikube ssh -- "sudo mv /root/kube-apiserver.yaml $M"
for i in $(seq 1 60); do kubectl get --raw /readyz >/dev/null 2>&1 && break; sleep 3; done
echo "restored: $(kubectl get --raw /readyz 2>&1)"
