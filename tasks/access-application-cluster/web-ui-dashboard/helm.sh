#!/usr/bin/env bash
# NOT from the docs: run helm from its container image (no local install). Uses your kubeconfig and minikube certs
# (mounted at the same paths) and the host network so 192.168.x.x:8443 is reachable. Repo cache in ./.helm-cache (gitignored).
# Usage: ./helm.sh <helm args...>
mkdir -p "$PWD/.helm-cache"
exec docker run --rm --network host --user "$(id -u):$(id -g)" \
  -e HOME=/tmp -e HELM_CACHE_HOME=/cache/cache -e HELM_CONFIG_HOME=/cache/config -e HELM_DATA_HOME=/cache/data \
  -v "$HOME/.kube:$HOME/.kube:ro" -v "$HOME/.minikube:$HOME/.minikube:ro" -e KUBECONFIG="$HOME/.kube/config" \
  -v "$PWD/.helm-cache:/cache" alpine/helm:3.19.0 "$@"
