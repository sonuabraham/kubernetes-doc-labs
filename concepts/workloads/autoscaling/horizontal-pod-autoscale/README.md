# Horizontal Pod Autoscaling – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/

> Needs **metrics-server**: `minikube addons enable metrics-server` (the HPA reads `metrics.k8s.io`).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **HPA** | An API object plus a controller (in kube-controller-manager) that adjusts the **replicas** of a Deployment/StatefulSet/ReplicaSet (anything with a `scale` subresource) to match a target metric. It doesn't apply to DaemonSets. |
| **Loop** | Every 15s (`--horizontal-pod-autoscaler-sync-period`): read metrics, compute `desired = ceil(current × currentMetric / target)`. |
| **Tolerance** | No change within ±10% of the target by default. Per HPA: `behavior.scaleUp/scaleDown.tolerance` (`HPAConfigurableTolerance`, on). |
| **Readiness** | Pods that aren't ready, or are just starting, are treated conservatively (0% on scale-up, 100% on scale-down), so set **CPU requests** and good readiness probes. |
| **Metric types** | `Resource` (pod average), `ContainerResource` (one container, e.g. ignore sidecars), `Pods` / `Object` (custom.metrics.k8s.io), `External` (external.metrics.k8s.io). Several metrics → the **max** desired replicas wins. |
| **behavior** | `scaleUp` / `scaleDown`: `policies` (`Pods` or `Percent` per `periodSeconds`), `selectPolicy` (Max, Min, Disabled), `stabilizationWindowSeconds` (scale-down default **300s**, scale-up 0). |
| **Flapping** | The stabilization window uses the highest recommendation in the window, so it doesn't drop too eagerly. |
| **Rolling update** | The HPA scales the Deployment, and the Deployment handles ReplicaSets. Don't set `replicas` in the manifest you `apply`, or apply fights the HPA. |
| **Scale to zero** | `minReplicas: 0` (`HPAScaleToZero`, beta, **on**), but only with at least one **Object/External** metric. |
| **Maintenance mode** | Set the target's `replicas` to 0 and the HPA stops acting (`ScalingActive=False, ScalingDisabled`). |

## The demo app
[00-php-apache.yaml](00-php-apache.yaml) is `php-apache` (`registry.k8s.io/hpa-example`, CPU request 200m) + Service. [01-hpa.yaml](01-hpa.yaml) is an `autoscaling/v2` HPA at 50% CPU on container `application`, 1–10 replicas, **30s** scale-down stabilization (lab speed), scale-up tolerance 5%. [02-load-generator.yaml](02-load-generator.yaml) is 4 busybox loops calling php-apache.
[behavior-snippets/](behavior-snippets/) holds the 10 YAML fragments from the docs page, **verbatim**: metric blocks and every `behavior` example (default behavior, limit scale-down rate, disable scale-down…).

---

## Lab 1 – Create, then generate load
```bash
cd concepts/workloads/autoscaling/horizontal-pod-autoscale
kubectl apply -f 00-php-apache.yaml -f 01-hpa.yaml
kubectl get hpa -n hpa-demo -w               # cpu: <unknown>/50% for the first ~30s (metrics not collected yet), then ~0%
kubectl apply -f 02-load-generator.yaml      # in another terminal; keep watching
```
Measured on this cluster:
```
+40s   cpu: 79%/50%    replicas 1
+60s   cpu: 79%/50%    replicas 2      <- ceil(1 × 79/50) = 2
+100s  cpu: 226%/50%   replicas 2
+120s  cpu: 226%/50%   replicas 5      <- ceil(2 × 226/50) = 10, capped by the default scale-up policy (max(100%, 4 pods) per 15s)
+160s  cpu: 147%/50%   replicas 5 -> 6 -> 10
```
```bash
kubectl describe hpa php-apache -n hpa-demo | sed -n '/Events/,$p'
#   SuccessfulRescale  New size: 2; reason: cpu container resource utilization (percentage of request) above target
#   SuccessfulRescale  New size: 5 ...   New size: 6 ...   New size: 10 ...
```

## Lab 2 – Scale down and stabilization
```bash
kubectl delete -f 02-load-generator.yaml
kubectl get hpa -n hpa-demo -w
```
What we saw: the HPA went **up** to 10 shortly *after* the load stopped (metrics-server averages over a window, so stale high readings arrive late), then back to **1** about 30s after the readings dropped (our `stabilizationWindowSeconds: 30`). With the default 300s you'd wait 5 minutes. That's deliberate, to avoid flapping.

## Lab 3 – Behavior variants (docs snippets)
Paste a snippet from [behavior-snippets/](behavior-snippets/) into `01-hpa.yaml`'s `spec.behavior` and re-run Labs 1–2:

| Snippet | Effect |
|---|---|
| `04-scaledown-stabilization-300.yaml` | the default 5-minute scale-down delay |
| `08-scaledown-limit-10-percent.yaml` | scale down by at most 10% per minute |
| `03-scaledown-policies-pods-and-percent.yaml` | 4 pods **or** 10%/minute, whichever removes more (selectPolicy Max) |
| `09-scaledown-select-min.yaml` | …whichever removes **fewer** (Min) |
| `10-scaledown-disabled.yaml` | never scale down automatically |
| `06-default-behavior.yaml` | what you get when `behavior` is omitted |
```bash
kubectl get hpa php-apache -n hpa-demo -o jsonpath='{.spec.behavior}' | jq .     # defaults are filled in by the API server
```

## Lab 4 – Scale to zero and maintenance mode
```bash
kubectl patch hpa php-apache -n hpa-demo -p '{"spec":{"minReplicas":0}}'
#   spec.metrics: Forbidden: must specify at least one Object or External metric to support scaling to zero replicas
kubectl scale deploy php-apache -n hpa-demo --replicas=0 ; sleep 30
kubectl get hpa php-apache -n hpa-demo -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
#   AbleToScale=True SucceededGetScale
#   ScalingActive=False ScalingDisabled         <- "implicit maintenance-mode deactivation"
kubectl scale deploy php-apache -n hpa-demo --replicas=1      # HPA takes over again
```

## Lab 5 – kubectl shortcuts
```bash
kubectl autoscale deployment php-apache -n hpa-demo --cpu-percent=50 --min=1 --max=10 --dry-run=client -o yaml
kubectl get hpa -n hpa-demo ; kubectl describe hpa php-apache -n hpa-demo
kubectl top pods -n hpa-demo                       # the numbers the HPA sees
```

---

## Useful commands
```bash
kubectl get hpa -w
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/<ns>/pods | jq .
kubectl explain hpa.spec.behavior.scaleDown
```

## Cleanup
```bash
./cleanup.sh
minikube addons disable metrics-server      # only if you don't need it for other labs
```
