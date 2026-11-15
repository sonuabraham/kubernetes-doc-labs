#!/usr/bin/env bash
cd "$(dirname "$0")"
[ -f .local_app.pid ] && kill "$(cat .local_app.pid)" 2>/dev/null; rm -f .local_app.pid
kubectl delete namespace tp-demo --ignore-not-found
