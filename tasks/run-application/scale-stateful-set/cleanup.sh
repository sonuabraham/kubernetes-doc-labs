#!/usr/bin/env bash
# Remove everything this lab created.
kubectl delete statefulset web webp --ignore-not-found
kubectl delete service web --ignore-not-found
kubectl wait --for=delete pod -l 'app.kubernetes.io/name in (web,webp)' --timeout=60s 2>/dev/null || true
kubectl delete pvc -l 'app.kubernetes.io/name in (web,webp)' --ignore-not-found
