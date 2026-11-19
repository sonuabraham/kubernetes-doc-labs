#!/usr/bin/env bash
# NOT from the docs – minikube stand-in for the page's two kind clusters (kind isn't installed here).
#   ./minikube-instead-of-kind.sh wo       ~ kind create cluster --name psa-wo-cluster-pss
#   ./minikube-instead-of-kind.sh with     ~ kind create cluster --name psa-with-cluster-pss --config cluster-config.yaml
#   ./minikube-instead-of-kind.sh delete   ~ kind delete cluster (both)
# "with": the docs' cluster-level-pss.yaml goes to /var/lib/minikube/certs/psa/ (already mounted into kube-apiserver,
# which is what cluster-config.yaml's extraMounts/extraVolumes do for kind), then the API server gets
# --admission-control-config-file. minikube switches the current context to the profile; "minikube start" (default profile) switches back.
set -euo pipefail
cd "$(dirname "$0")"
V=v1.37.0
case ${1:?wo|with|delete} in
  wo)   minikube start -p psa-wo-cluster-pss --memory 2048 --cpus 2 --kubernetes-version $V ;;
  with) P=psa-with-cluster-pss
        minikube start -p $P --memory 2048 --cpus 2 --kubernetes-version $V
        minikube -p $P ssh -- sudo mkdir -p /var/lib/minikube/certs/psa
        minikube -p $P cp cluster-level-pss.yaml /var/lib/minikube/certs/psa/cluster-level-pss.yaml
        minikube start -p $P --extra-config=apiserver.admission-control-config-file=/var/lib/minikube/certs/psa/cluster-level-pss.yaml
        kubectl --context $P -n kube-system get pod -l component=kube-apiserver -o jsonpath='{.items[0].spec.containers[0].command}' \
          | tr , '\n' | grep admission-control-config-file ;;
  delete) minikube delete -p psa-with-cluster-pss || true; minikube delete -p psa-wo-cluster-pss || true
        echo "now: minikube start   (restarts the default cluster and its kubectl context)" ;;
esac
