# Monitoring in Kubernetes – Section Page

Based on: https://kubernetes.io/docs/tasks/debug/monitoring/

> This docs page is only a list of links. The hands-on work is in the concept labs it points to:

| Docs link | Lab in this repo |
|---|---|
| Metrics For Kubernetes System Components | [concepts/cluster-administration/system-metrics](../../../concepts/cluster-administration/system-metrics/): `/metrics` of each component, stability levels, `kubernetes_feature_enabled` |
| Traces For Kubernetes System Components | [concepts/cluster-administration/system-traces](../../../concepts/cluster-administration/system-traces/): OpenTelemetry tracing of apiserver/kubelet |

See also, in this section: [debug-cluster/resource-metrics-pipeline](../debug-cluster/resource-metrics-pipeline/) and
[debug-cluster/resource-usage-monitoring](../debug-cluster/resource-usage-monitoring/).
Quick reminders:
```bash
kubectl get --raw /metrics | grep apiserver_request_total | head
kubectl get --raw /api/v1/nodes/minikube/proxy/metrics/resource
kubectl top nodes; kubectl top pods -A
```
