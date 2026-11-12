#!/usr/bin/env bash
# Throwaway single-node profile for the kubeadm labs. minikube bootstraps nodes WITH kubeadm, so the real
# kubeadm binary and a real kubeadm control plane are there to work with. Starts at v1.36 so the upgrade lab
# has something to upgrade.  When done: minikube stop -p kubeadm-lab ; kubectl config use-context minikube
minikube start -p kubeadm-lab --memory 2200 --cpus 2 --kubernetes-version ${1:-v1.36.0} --container-runtime=containerd
kubectl config use-context minikube >/dev/null       # don't leave the default context pointing at the lab
