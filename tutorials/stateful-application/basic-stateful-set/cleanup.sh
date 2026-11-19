#!/usr/bin/env bash
# Cleanup for "StatefulSet Basics" (the docs' cleanup commands, idempotent).
kubectl delete sts web --ignore-not-found
kubectl delete svc nginx --ignore-not-found
kubectl delete pvc www-web-0 www-web-1 www-web-2 www-web-3 www-web-4 --ignore-not-found
kubectl delete pod dns-test --ignore-not-found --now
