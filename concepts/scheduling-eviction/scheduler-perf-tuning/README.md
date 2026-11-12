# Scheduler Performance Tuning – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/scheduler-perf-tuning/

> The docs' config is **verbatim** in [kubeschedulerconfig-v1alpha1-docs.yaml](kubeschedulerconfig-v1alpha1-docs.yaml). It uses the long-removed `v1alpha1` API, so [00-perf-scheduler.yaml](00-perf-scheduler.yaml) expresses the same thing in `v1`, as three profiles of one extra scheduler. The setting only matters for clusters with **more than 100 nodes**, so this lab uses **250 fake nodes**: `../fake-nodes.sh up 250`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **percentageOfNodesToScore** | Once this share of nodes has been found **feasible**, the scheduler stops filtering and scores just those. Trades placement quality for throughput in large clusters. |
| **Default (unset/0)** | Adaptive: **50% − (nodes/125)%** (50% at 100 nodes, 10% at 5000), floor **5%**. |
| **Minimum** | Always at least **100** feasible nodes (or all of them). Values < 5 are treated as 5 (adaptive floor), > 100 as 100. |
| **Where** | Top-level or per profile in `KubeSchedulerConfiguration` (v1). |
| **Fairness** | Nodes are walked **round-robin** starting where the previous Pod stopped, alternating zones, so every node gets considered over time. |
| **Advice** | Don't go below 10% unless throughput is critical and placement quality doesn't matter. |

---

## Step 1
```bash
cd concepts/scheduling-eviction
./fake-nodes.sh down ; ./fake-nodes.sh up 250       # ~12s to create; wait until all report Ready
cd scheduler-perf-tuning
kubectl apply -f 00-perf-scheduler.yaml               # profiles: adaptive, pct-10, pct-100 (logs at -v=2)
```

## Lab 1 – How many nodes get looked at
```bash
for s in adaptive pct-10 pct-100; do for i in 1 2 3; do
  kubectl run $s-$i -n perf-demo --image=registry.k8s.io/pause:3.8 --overrides="{\"spec\":{\"schedulerName\":\"$s\",\"nodeSelector\":{\"type\":\"fake\"}}}"; done; done
kubectl logs -n perf-demo deploy/perf-scheduler | grep 'Successfully bound' | grep -o 'pod="perf-demo/[^"]*".*' | sed 's/node="[^"]*" //' | sort
#   adaptive-1  evaluatedNodes=209 feasibleNodes=120     <- 50 - 251/125 = 48% of 251 ≈ 120: stops once 120 feasible found
#   pct-10-1    evaluatedNodes=182 feasibleNodes=100     <- 10% = 25, raised to the 100-node minimum
#   pct-100-1   evaluatedNodes=251 feasibleNodes=145     <- every node checked
```
`evaluatedNodes` > `feasibleNodes` because some fake nodes were briefly unhealthy and filtered out. With 250 nodes the single heartbeat loop sometimes lags. That's also why pct-100 found ~146 feasible, not 250.

## Lab 2 – The docs' config doesn't load any more
```bash
kubectl create cm docs-config -n perf-demo --from-file=config.yaml=kubeschedulerconfig-v1alpha1-docs.yaml
kubectl run cfgtest -n perf-demo --image=registry.k8s.io/kube-scheduler:v1.37.0 --restart=Never --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"minikube"},"volumes":[{"name":"c","configMap":{"name":"docs-config"}}],"containers":[{"name":"c","image":"registry.k8s.io/kube-scheduler:v1.37.0","command":["kube-scheduler","--config=/etc/c/config.yaml"],"volumeMounts":[{"name":"c","mountPath":"/etc/c"}]}]}}'
kubectl logs cfgtest -n perf-demo | tail -1
#   "command failed" err="no kind \"KubeSchedulerConfiguration\" is registered for version \"kubescheduler.config.k8s.io/v1alpha1\" ..."
```
Use `kubescheduler.config.k8s.io/v1` with `percentageOfNodesToScore: 50` (no `algorithmSource`).

---

## Useful commands
```bash
kubectl logs -n perf-demo deploy/perf-scheduler | grep -o 'evaluatedNodes=[0-9]* feasibleNodes=[0-9]*'
kubectl get nodes --no-headers | wc -l
```

## Cleanup
```bash
./cleanup.sh       # namespace, RBAC, and shrinks the fake nodes back to 3
```
