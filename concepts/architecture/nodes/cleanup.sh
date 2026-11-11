#!/usr/bin/env bash
C="--context arch-lab"
minikube node start m02 -p arch-lab >/dev/null 2>&1      # in case it is still stopped
kubectl $C uncordon arch-lab-m02 >/dev/null 2>&1
kubectl $C label node arch-lab-m02 disktype- node-role.kubernetes.io/worker- >/dev/null 2>&1
kubectl $C delete node 10.240.79.157 --ignore-not-found
kubectl $C delete namespace nodes-demo --ignore-not-found
