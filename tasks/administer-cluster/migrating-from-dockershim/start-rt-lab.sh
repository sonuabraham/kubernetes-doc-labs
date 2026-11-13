#!/usr/bin/env bash
# Throwaway single-node profile whose container runtime is Docker Engine (through cri-dockerd, the external
# replacement for the removed dockershim). Used by all labs in this folder.  Done: minikube delete -p rt-lab
minikube start -p rt-lab --container-runtime=docker --memory 2200 --cpus 2 --kubernetes-version v1.37.0
kubectl config use-context minikube >/dev/null      # keep the default context on the main cluster
