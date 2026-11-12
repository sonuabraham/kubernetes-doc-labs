#!/usr/bin/env bash
"$(dirname "$0")"/../force-delete-on-fake.sh apn-demo
kubectl delete namespace apn-demo --ignore-not-found
kubectl delete clusterrolebinding apn-foo-scheduler apn-foo-volume-scheduler --ignore-not-found
kubectl delete rolebinding apn-foo-auth-reader -n kube-system --ignore-not-found
kubectl label node minikube topology.kubernetes.io/zone- topology.kubernetes.io/region- >/dev/null 2>&1
for n in fake-1 fake-2 fake-3; do kubectl label node $n label-1- label-2- node-pool- scheduler-profile- >/dev/null 2>&1; done
kubectl label node fake-2 topology.kubernetes.io/zone=zone-b --overwrite >/dev/null 2>&1
true
