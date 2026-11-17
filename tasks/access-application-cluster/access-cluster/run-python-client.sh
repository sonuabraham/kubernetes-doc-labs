#!/usr/bin/env bash
# NOT from the docs: run list_namespaces.py in a python container (pip install kubernetes inside), with your kubeconfig
# and minikube certs mounted at the same paths and the host network (so the minikube IP is reachable).
exec docker run --rm --network host \
  -v "$HOME/.kube:$HOME/.kube:ro" -v "$HOME/.minikube:$HOME/.minikube:ro" -e KUBECONFIG="$HOME/.kube/config" \
  -v "$PWD/list_namespaces.py:/app/list_namespaces.py:ro" python:3.13-slim \
  sh -c 'pip install -q --root-user-action=ignore kubernetes==34.1.0 2>/dev/null && python /app/list_namespaces.py'
