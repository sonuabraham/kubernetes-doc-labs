#!/usr/bin/env bash
# Cleanup for "Configure a Pod to Use a PersistentVolume for Storage" (docs cleanup + the GID demo).
kubectl delete pod test task-pv-pod gid-demo --ignore-not-found --now
kubectl delete pvc task-pv-claim pv1-claim --ignore-not-found
kubectl delete pv task-pv-volume pv1 --ignore-not-found
# docs: remove the files on the node (rm -rf instead of the docs' rm/rmdir sequence, so it also works after a partial run)
minikube ssh 'sudo rm -rf /mnt/data /mnt/data-gid'
