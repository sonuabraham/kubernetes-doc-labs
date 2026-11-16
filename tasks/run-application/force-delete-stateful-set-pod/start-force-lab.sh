#!/usr/bin/env bash
# NOT from the docs: a throwaway 2-node minikube profile "force-lab" for this lab.
# Stops the default profile first (two clusters at once can exhaust inotify limits on the host).
set -euo pipefail
minikube stop || true
minikube start -p force-lab --nodes 2 --driver=docker
kubectl wait --for=condition=Ready node --all --timeout=180s
kubectl get nodes
