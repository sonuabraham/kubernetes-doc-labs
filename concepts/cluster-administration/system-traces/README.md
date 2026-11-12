# Traces For Kubernetes System Components – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/system-traces/

> The docs' 3 configs are **verbatim**: [otel-collector-config-docs.yaml](otel-collector-config-docs.yaml), [apiserver-tracing-config.yaml](apiserver-tracing-config.yaml), [kubelet-tracing-config-excerpt.yaml](kubelet-tracing-config-excerpt.yaml). Tracing needs API-server and kubelet configuration plus a collector, so it runs on a throwaway profile **`trace-lab`** ([start-tracing-lab.sh](start-tracing-lab.sh)): an OpenTelemetry Collector on the node's host network ([00-otel-collector.yaml](00-otel-collector.yaml), debug exporter), the API server's `--tracing-config-file`, and the kubelet's `tracing:` block. Sampling is raised from 100 per million to **all** requests so spans show up immediately.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **What** | OpenTelemetry spans (OTLP/gRPC) from kube-apiserver, kubelet (+ CRI calls to containerd) and etcd, so one request can be followed across components. |
| **Default endpoint** | `localhost:4317`, so run a collector on each control-plane node / node (host network, DaemonSet). |
| **API server** | `--tracing-config-file` → `TracingConfiguration {endpoint, samplingRatePerMillion}`. Incoming W3C trace context is honoured. |
| **kubelet** | `KubeletConfiguration.tracing`: spans for syncPod and every CRI gRPC call. |
| **Sampling** | Per million. The docs' 100 = 0.01%. Production wants low rates (or parent-based sampling). |
| **Stability** | Alpha/beta span names and attributes: don't build alerts on them. |

---

## Lab – Turn it on and look at the spans
```bash
cd concepts/cluster-administration/system-traces
./start-tracing-lab.sh
#   --tracing-config-file=/var/lib/minikube/certs/tracing-config.yaml
kubectl --context trace-lab create ns traced ; kubectl --context trace-lab run traced-pod -n traced --image=registry.k8s.io/pause:3.8
kubectl --context trace-lab logs -n kube-system otel-collector | grep -c '^Span #'           # 4851 spans within ~1 minute
kubectl --context trace-lab logs -n kube-system otel-collector | grep 'service.name: Str' | sort | uniq -c
#   11  -> service.name: Str(apiserver)
#    4  -> service.name: Str(kubelet)
```
API server spans: one per request handler stage (`authentication`, `authorization`, `audit`, `priorityandfairness`, `constrainedimpersonation` … 420 each), `etcdserverpb.KV/Range` (etcd calls, 382), and request spans such as `GET /api/v1/namespaces/{:namespace}/pods/{:name}`. Kubelet spans: `syncPod` (27) and every CRI call (`runtime.v1.RuntimeService/ContainerStatus` 53, `ListContainers` 48, `ListPodSandbox` 44, `ImageService/ImageStatus` …).

The docs' collector config as written **doesn't start**:
```bash
otelcol validate --config=otel-collector-config-docs.yaml
#   Error decoding 'exporters': unknown type: "exporters" for id: "exporters" (valid values: [otlphttp file prometheus ... debug ...])
```
It nests `exporters:` inside `exporters:`. [00-otel-collector.yaml](00-otel-collector.yaml) has it fixed and listens on `127.0.0.1:4317`.

```bash
./cleanup.sh     # stops trace-lab
```

---

## Useful commands
```bash
kubectl get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[]' | grep tracing
kubectl get --raw /api/v1/nodes/<n>/proxy/configz | jq .kubeletconfig.tracing
```
