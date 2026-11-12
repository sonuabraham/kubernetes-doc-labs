#!/usr/bin/env bash
minikube ssh -- "sudo rm -f /etc/kubernetes/manifests/sneaky-static.yaml; sudo ctr -n bypass task kill -s KILL hidden 2>/dev/null; sleep 1; sudo ctr -n bypass task rm hidden 2>/dev/null; sudo ctr -n bypass container rm hidden 2>/dev/null; sudo ctr -n bypass image rm docker.io/library/busybox:1.36 2>/dev/null; sleep 3; sudo ctr namespace rm bypass 2>/dev/null" >/dev/null 2>&1
kubectl delete namespace bypass-demo --ignore-not-found
