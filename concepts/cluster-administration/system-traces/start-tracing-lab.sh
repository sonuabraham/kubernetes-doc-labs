#!/usr/bin/env bash
# Throwaway profile "trace-lab": collector on localhost:4317, then
#   kube-apiserver --tracing-config-file (the docs' TracingConfiguration, but sampling 1000000 = every request)
#   kubelet tracing: {samplingRatePerMillion: 1000000}
set -euo pipefail
cd "$(dirname "$0")"; P=trace-lab
minikube start -p $P --memory 2048 --cpus 2 --kubernetes-version v1.37.0 >/dev/null
until kubectl --context $P get sa default -n kube-system >/dev/null 2>&1; do sleep 2; done      # fresh cluster: wait for the default SA
kubectl --context $P apply -f 00-otel-collector.yaml >/dev/null
kubectl --context $P wait --for=condition=Ready pod/otel-collector -n kube-system --timeout=180s >/dev/null
sed 's/samplingRatePerMillion: 100$/samplingRatePerMillion: 1000000/' apiserver-tracing-config.yaml > /tmp/tracing.yaml
minikube -p $P cp /tmp/tracing.yaml /var/lib/minikube/certs/tracing-config.yaml >/dev/null
minikube -p $P ssh -- "sudo sh -c '
  m=/etc/kubernetes/manifests/kube-apiserver.yaml
  grep -q tracing-config-file \$m || sed -i \"s#    - kube-apiserver#    - kube-apiserver\n    - --tracing-config-file=/var/lib/minikube/certs/tracing-config.yaml#\" \$m
  f=/var/lib/kubelet/config.yaml; sed -i \"/^tracing:/,+1d\" \$f; printf \"tracing:\n  samplingRatePerMillion: 1000000\n\" >> \$f
  systemctl restart kubelet'"
until kubectl --context $P get --raw /readyz >/dev/null 2>&1; do sleep 3; done
kubectl --context $P get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[]' | grep tracing
