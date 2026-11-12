#!/usr/bin/env bash
# One example of each signal type from the page (read-only). Needs: minikube addons enable metrics-server
echo "== METRICS: resource metrics API (metrics-server)";      kubectl top node
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes/minikube | jq -c '{cpu: .usage.cpu, memory: .usage.memory, window}'
echo "== METRICS: component /metrics (Prometheus format)";      kubectl get --raw /metrics | grep -c '^apiserver_request_total' | sed 's/$/ apiserver_request_total series/'
echo "== LOGS: container stdout/stderr via the kubelet";        kubectl logs -n kube-system -l component=kube-scheduler --tail=1 | cut -c1-140
echo "== LOGS: node services (systemd journal)";                minikube ssh -- "sudo journalctl -u kubelet --no-pager -n 1" | cut -c1-140
echo "== TRACES: OpenTelemetry tracing configured?";           kubectl get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[]' | grep -i tracing || echo "no --tracing-config-file (off)"
