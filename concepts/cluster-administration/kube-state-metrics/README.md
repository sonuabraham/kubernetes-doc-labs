# Metrics for Kubernetes Object States (kube-state-metrics) – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/kube-state-metrics/

> The docs' alert rule is **verbatim** in [alert-pods-blocked-terminating.yaml](alert-pods-blocked-terminating.yaml), and the docs' query in [query-not-ready.promql](query-not-ready.promql). kube-state-metrics is an add-on: [00-kube-state-metrics.yaml](00-kube-state-metrics.yaml) is a minimal install of the official image (`registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.15.0`, list/watch RBAC). There's no Prometheus here, so the expressions are evaluated by reading the raw series with grep.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **kube-state-metrics (KSM)** | Watches API objects and exposes their **state** as metrics (`kube_pod_status_ready`, `kube_deployment_status_replicas_available`, `kube_pod_deletion_timestamp`, …). It doesn't measure resource usage (that's metrics-server / cAdvisor). |
| **vs component metrics** | Component `/metrics` = how a component is performing. KSM = what the objects look like. |
| **Use** | PromQL queries for dashboards and alert rules (e.g. Pods stuck terminating, Deployments short of replicas). |
| **Stability** | KSM metrics have their own stability levels (`[STABLE]` in `# HELP`). |

---

## Step 1
```bash
cd concepts/cluster-administration/kube-state-metrics
kubectl apply -f 00-kube-state-metrics.yaml ; kubectl rollout status deploy/kube-state-metrics -n ksm
../../scheduling-eviction/fake-nodes.sh up 1
kubectl create ns ksm-demo
# never-ready: readiness probe "false"; stuck: bound to fake-1, then deleted (can't finish terminating)
./scrape.sh ksm.txt
grep -vc '^#' ksm.txt ; grep -c '^# HELP' ksm.txt          # 1171 series, 146 metric families
```

## Lab 1 – The docs' query: Pods that aren't Ready
`count(kube_pod_status_ready{condition="false"}) by (namespace, pod)`, by hand:
```bash
grep '^kube_pod_status_ready{.*condition="false"} 1' ksm.txt | sed 's/.*namespace="\([^"]*\)",pod="\([^"]*\)".*/\1\/\2/'
#   ksm-demo/never-ready
#   ksm/curl                 <- the scrape Pod itself: Completed Pods are "not ready" too - filter by phase in real queries
```

## Lab 2 – The docs' alert: Pods blocked in Terminating
`count(kube_pod_deletion_timestamp) by (namespace, pod) * count(kube_pod_status_reason{reason="NodeLost"} == 0) by (namespace, pod) > 0` for 5m:
```bash
grep '^kube_pod_deletion_timestamp' ksm.txt
#   kube_pod_deletion_timestamp{namespace="ksm-demo",pod="stuck",uid="f32b…"} 1.79447039e+09      <- deletion requested
grep 'kube_pod_status_reason{namespace="ksm-demo",pod="stuck".*NodeLost' ksm.txt
#   ...reason="NodeLost"} 0                                                                          <- not explained by a lost node
```
Both factors exist for `ksm-demo/stuck`, so after 5 minutes `PodsBlockedInTerminatingState` would page someone. (Here the node isn't lost, it's a fake with no kubelet. On a real cluster that's often a finalizer, or a node that's down without being marked lost.)

---

## Useful commands
```bash
grep '^# HELP kube_pod_' ksm.txt | head
kubectl get pods -A --field-selector status.phase=Running -o json | jq '[.items[] | select(.metadata.deletionTimestamp)] | length'   # the same question, asked of the API
```

## Cleanup
```bash
./cleanup.sh
```
