#!/usr/bin/env bash
# Throwaway profile "probe-lab" with the two ALPHA probe gates (off by default in v1.37):
#   H2CContainerProbe      - httpGet.protocol: HTTP2 (h2c)
#   GRPCContainerProbeTLS  - grpc.mode: TLS
# Stop the default cluster first (`minikube stop`): two clusters exhaust this host's inotify instances.
minikube start -p probe-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 \
  --feature-gates=H2CContainerProbe=true,GRPCContainerProbeTLS=true
kubectl config use-context minikube
kubectl --context probe-lab get --raw /metrics | grep -E 'kubernetes_feature_enabled\{name="(H2CContainerProbe|GRPCContainerProbeTLS)"'
echo "Use: kubectl --context probe-lab ...   When done: minikube delete -p probe-lab; minikube start"
