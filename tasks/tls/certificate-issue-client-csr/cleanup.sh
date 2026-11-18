#!/usr/bin/env bash
# Remove everything this lab created (cluster objects + local key/cert/kubeconfig; your ~/.kube/config was never touched).
cd "$(dirname "$0")" || exit 1
kubectl --context minikube delete csr myuser myuser-dev bad-usage short --ignore-not-found
kubectl --context minikube delete rolebinding developer-binding-myuser --ignore-not-found
kubectl --context minikube delete role developer --ignore-not-found
rm -f myuser.key myuser.csr myuser.crt kubeconfig-lab
