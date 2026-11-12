# Observability – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/observability/

> An overview page. [tour.sh](tour.sh) (read-only) pulls **one example of each signal** from this cluster. The deep dives are separate labs: [system-metrics](../system-metrics/), [kube-state-metrics](../kube-state-metrics/), [logging](../logging/), [system-logs](../system-logs/), [system-traces](../system-traces/).

## Key ideas (read first)

| Signal | Built into Kubernetes | Typical tooling |
|---|---|---|
| **Metrics** | Components expose `/metrics` (Prometheus text). **Metrics API** (`metrics.k8s.io`, served by metrics-server) for `kubectl top`, HPA, VPA. Custom/external metrics APIs for adapters. | Prometheus, OpenTelemetry Collector, kube-state-metrics, Grafana |
| **Logs** | Containers → stdout/stderr → files on the node, read by `kubectl logs`. System components → journald or files (klog, structured/JSON). | Fluent Bit, Vector, Loki, Elasticsearch |
| **Traces** | API server, kubelet, etcd and containerd can emit OpenTelemetry spans (OTLP) when configured. | OpenTelemetry Collector, Jaeger, Tempo |

---

## Lab – One of each
```bash
cd concepts/cluster-administration/observability
minikube addons enable metrics-server
./tour.sh
```
Measured:
```
== METRICS: resource metrics API     minikube 219m 2% 1726Mi 5%
                                     {"cpu":"218016872n","memory":"1768092Ki","window":"1m0.217s"}    <- raw API behind kubectl top
== METRICS: component /metrics       699 apiserver_request_total series
== LOGS: container                   E1112 04:28:17 schedule_one.go:1261] "Error updating pod" err="pods \"b\" not found" ...
== LOGS: node services               Nov 12 07:37:53 minikube kubelet[1381]: I1112 ... "RemoveContainer" ...
== TRACES                            no --tracing-config-file (off)
```
The scheduler log line is a leftover from the gang-scheduling labs (Pods force-deleted while being scheduled), which is what logs are for. Tracing is off by default everywhere, and [system-traces](../system-traces/) turns it on.

---

## Useful commands
```bash
kubectl top node|pod ; kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods | jq '.items | length'
kubectl get --raw /metrics | head
kubectl logs <pod> [-c c] [--previous] ; minikube ssh -- sudo journalctl -u kubelet
```

## Cleanup
Nothing to clean up.
