# Autoscaling Workloads – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/autoscaling/

> Sub-pages: [horizontal-pod-autoscale](horizontal-pod-autoscale/), [vertical-pod-autoscale](vertical-pod-autoscale/).

## Key ideas (read first)

| Approach | What changes | Built in? |
|---|---|---|
| **Manual horizontal** | `kubectl scale` → number of replicas | yes |
| **Manual vertical** | Patch the template, or **resize in place** (`--subresource resize`) → CPU/memory per Pod | yes |
| **HPA** | Replicas, from observed metrics (CPU, memory, custom, external) | yes (needs metrics-server) |
| **VPA** | Requests/limits, from observed usage | **add-on** (CRDs + components, needs metrics-server). No in-place resize integration yet. |
| **Cluster Proportional Autoscaler** | Replicas ∝ number of nodes/cores (for example cluster DNS) | add-on |
| **Cluster Proportional Vertical Autoscaler** | Requests ∝ cluster size (beta) | add-on |
| **KEDA** (CNCF graduated) | Replicas from **events** (queue length…), including scale to zero. Its `Cron` scaler covers schedules. | add-on |
| **Schedules** | Scale in/out at set times | KEDA Cron, or a CronJob (below) |
| **Node autoscaling** | Adds or removes **nodes** | see `../../cluster-administration/node-autoscaling` |

## The demo app
[00-app.yaml](00-app.yaml) is Deployment `web` (busybox, requests 100m/32Mi). [01-schedule-scaler.yaml](01-schedule-scaler.yaml) is a "poor man's KEDA Cron scaler": two CronJobs running `kubectl scale` with a tightly scoped ServiceAccount.

---

## Lab 1 – Manual horizontal scaling
```bash
cd concepts/workloads/autoscaling
kubectl apply -f 00-app.yaml
kubectl scale deploy/web --replicas=3 -n autoscaling-demo
kubectl get deploy web -n autoscaling-demo
```

## Lab 2 – Manual vertical scaling, in place
```bash
P=$(kubectl get pod -n autoscaling-demo -l app=web -o name | head -1)
kubectl patch $P -n autoscaling-demo --subresource resize \
  -p '{"spec":{"containers":[{"name":"web","resources":{"requests":{"cpu":"150m"},"limits":{"cpu":"300m"}}}]}}'
kubectl get $P -n autoscaling-demo -o jsonpath='{.status.containerStatuses[0].resources.limits.cpu} restarts={.status.containerStatuses[0].restartCount}{"\n"}'
#   300m restarts=0         <- bigger without a restart (InPlacePodVerticalScaling)
```
That changed **one Pod**. Changing the Deployment template instead (`kubectl set resources deploy/web …`) rolls out new Pods.

## Lab 3 – Automatic horizontal scaling
See [horizontal-pod-autoscale](horizontal-pod-autoscale/): php-apache under load, 1 → 10 → 1 replicas.

## Lab 4 – Schedule-based scaling with a CronJob
```bash
kubectl apply -f 01-schedule-scaler.yaml
while true; do echo "$(date +%M:%S) replicas=$(kubectl get deploy web -n autoscaling-demo -o jsonpath='{.spec.replicas}')"; sleep 20; done
```
Measured:
```
32:05 replicas=4     <- even minute: scale-up CronJob
33:06 replicas=1     <- odd minute: scale-down CronJob
34:07 replicas=4
```
The CronJob's ServiceAccount may only `get/patch/update` `deployments` and `deployments/scale` in this namespace (least privilege). Don't combine this with an HPA on the same Deployment, because they would fight. KEDA's Cron scaler drives an HPA instead.

## Lab 5 – Event-driven and cluster-proportional (reading)
These need third-party controllers that aren't part of Kubernetes:
- KEDA: `ScaledObject` → it creates and manages an HPA fed with external metrics (queue depth, Kafka lag, Cron…).
- Cluster Proportional Autoscaler: a Deployment that watches node/core counts and scales a target, often CoreDNS: `replicas = max(ceil(cores/coresPerReplica), ceil(nodes/nodesPerReplica))`.
```bash
kubectl get deploy coredns -n kube-system      # 1 replica on minikube - nothing scales it here
```

---

## Useful commands
```bash
kubectl scale deploy/<d> --replicas=N
kubectl autoscale deploy/<d> --min=1 --max=5 --cpu-percent=60
kubectl patch pod <p> --subresource resize -p '...'
kubectl top pods
```

## Cleanup
```bash
./cleanup.sh
```
