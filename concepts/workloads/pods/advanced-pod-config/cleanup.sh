#!/usr/bin/env bash
kubectl delete namespace adv-a adv-b --ignore-not-found
kubectl delete priorityclass high-priority --ignore-not-found
kubectl delete runtimeclass kvisor-runtime --ignore-not-found
kubectl label node minikube disktype- topology.kubernetes.io/zone- >/dev/null 2>&1
