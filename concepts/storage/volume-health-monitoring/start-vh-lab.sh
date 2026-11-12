#!/usr/bin/env bash
# A small minikube profile with the alpha CSIVolumeHealth gate on (apiserver + kubelet), to see the new status fields stored.
minikube start -p vh-lab --memory 2048 --cpus 2 --kubernetes-version v1.37.0 --feature-gates=CSIVolumeHealth=true
echo "When done: minikube stop -p vh-lab (or delete) ; kubectl config use-context minikube"
