#!/usr/bin/env bash
# NOT from the docs: write ./kubeconfig-socks5 = your minikube kubeconfig (certs embedded) with
#   server: https://localhost:8443          <- "localhost" as seen FROM THE BASTION (the minikube node)
#   proxy-url: socks5://localhost:1080     <- the docs' proxy-url field; kubeconfig rejects socks5h; Go's socks5 dialer sends the host NAME to the proxy anyway
cd "$(dirname "$0")" || exit 1
kubectl config view --minify --flatten --context minikube | cat > kubeconfig-socks5
kubectl --kubeconfig kubeconfig-socks5 config set-cluster minikube --server=https://localhost:8443 >/dev/null
kubectl --kubeconfig kubeconfig-socks5 config set clusters.minikube.proxy-url socks5://localhost:1080 >/dev/null
grep -E 'server:|proxy-url:' kubeconfig-socks5
