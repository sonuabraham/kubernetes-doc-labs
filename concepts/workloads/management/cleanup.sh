#!/usr/bin/env bash
kubectl delete -f application/nginx-app.yaml -n mgmt-demo --ignore-not-found >/dev/null 2>&1
kubectl delete namespace mgmt-demo development staging guestbook-demo --ignore-not-found
