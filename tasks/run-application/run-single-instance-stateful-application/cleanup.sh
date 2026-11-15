#!/usr/bin/env bash
# Remove everything this lab created, including the hostPath data on the minikube node
# (otherwise the next run starts with the old database and old root password).
kubectl delete pod mysql-client --ignore-not-found --wait=false
kubectl delete deployment,svc mysql --ignore-not-found
kubectl delete pvc mysql-pv-claim --ignore-not-found
kubectl delete pv mysql-pv-volume --ignore-not-found
minikube ssh -- sudo rm -rf /mnt/data
