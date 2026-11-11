#!/usr/bin/env bash
kubectl delete namespace vol-demo vol-ed1 vol-ed2 vol-ed3 vol-nfs --ignore-not-found
kubectl delete pv example-pv --ignore-not-found
kubectl delete pod image-volume rro -n default --ignore-not-found
kubectl delete pod my-pod -n default --ignore-not-found
minikube ssh -- "sudo umount /mnt/tmpfs 2>/dev/null; sudo rm -rf /var/local/aaa" >/dev/null 2>&1
