#!/usr/bin/env bash
# Throwaway profile "volopt-lab" with two ALPHA gates (off by default in v1.37), used by
#   configure-emptydir-volume-mode  (EmptyDirVolumeMode:     emptyDir.mode)
#   configure-bind-mount-options    (VolumeBindMountOptions: volumeMounts[].bindMountOptions)
# Stop the default cluster first (`minikube stop`): two clusters exhaust this host's inotify instances.
minikube start -p volopt-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 \
  --feature-gates=EmptyDirVolumeMode=true,VolumeBindMountOptions=true
kubectl config use-context minikube >/dev/null
kubectl --context volopt-lab get --raw /metrics | grep -E 'kubernetes_feature_enabled\{name="(EmptyDirVolumeMode|VolumeBindMountOptions)"'
echo "Use: kubectl --context volopt-lab ...   When done: minikube delete -p volopt-lab; minikube start"
