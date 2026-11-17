#!/usr/bin/env bash
# Remove everything this lab created.
S=${PF_PID_FILE:-/tmp/dashboard-pf.pid}
[ -f "$S" ] && kill "$(cat "$S")" 2>/dev/null; rm -f "$S"
kubectl delete deployment,service dash-nginx --ignore-not-found
kubectl delete -f dashboard-adminuser.yaml --ignore-not-found
./helm.sh uninstall kubernetes-dashboard --namespace kubernetes-dashboard
kubectl delete namespace kubernetes-dashboard --ignore-not-found
