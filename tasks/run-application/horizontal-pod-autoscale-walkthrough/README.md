# HorizontalPodAutoscaler Walkthrough – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/

> Runs on the default **minikube** cluster with the **metrics-server** addon (`minikube addons enable metrics-server`), `default` namespace.
> Files (docs, **verbatim**): [php-apache.yaml](php-apache.yaml), [hpa-php-apache.yaml](hpa-php-apache.yaml) (declarative HPA),
> [hpa-multiple-metrics.yaml](hpa-multiple-metrics.yaml) (the inline multi-metric example). Not from the docs:
> [hpa-multiple-metrics-fixed.yaml](hpa-multiple-metrics-fixed.yaml), [watch-hpa.sh](watch-hpa.sh) (prints HPA + Deployment every 15 s).
>
> **Found:**
> 1. The inline multi-metric YAML can't be applied: it includes `status:` with `lastScaleTime: <some-time>`
>    (`parsing time "<some-time>" … cannot parse`). The `-fixed` file drops the status block.
> 2. The page says "each pod requests 200 milli-cores by `kubectl run`". The request comes from the manifest, not `kubectl run`.
>    `kubectl get hpa` now prints `cpu: 203%/50%` and `Deployment/php-apache` (no `/scale`).
> 3. Scale-down went 7 → **3** → 1, not straight to 1 (see Lab 3).
> 4. Measuring needs an awake machine: a laptop suspend during the run gave nonsense samples (clock jumps). Re-run if that happens.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Formula | `desired = ceil(current × currentMetric / target)`; CPU % is of the **request** (200m) |
| Metrics | metrics-server refreshes about every 60 s, so the HPA sees new load up to a minute late |
| Scale-up | fast (default policy: +100% or +4 Pods per 15 s, whichever is more) |
| Scale-down | 5-minute **stabilization window**: uses the highest recommendation of the last 5 min |
| Several metrics | one recommendation per metric, the **largest** wins; invalid metrics block scale-down, not scale-up |
| Conditions | `AbleToScale`, `ScalingActive`, `ScalingLimited` (+ `ScaledToZero` in this version) |

---

## Step 0
```bash
cd tasks/run-application/horizontal-pod-autoscale-walkthrough
minikube addons enable metrics-server
kubectl top nodes                              # works = Metrics API ready (after a restart it can take a minute)
```

## Lab 1 – App + HPA (docs)
```bash
kubectl apply -f php-apache.yaml
kubectl autoscale deployment php-apache --cpu=50% --min=1 --max=10
kubectl get hpa
#   php-apache   Deployment/php-apache   cpu: 0%/50%   1   10   1      <- shows cpu: <unknown> for the first ~minute
```

## Lab 2 – Load → scale up (docs)
The docs run the load generator interactively (`-i --tty --rm`). Here it runs in the background:
```bash
kubectl run load-generator --image=busybox:1.28 --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"
./watch-hpa.sh 240
#      0s  cpu: 0%/50% 1 10 1 | deploy 1/1
#     61s  cpu: 203%/50% 1 10 1 | deploy 2/4      <- first metric with load; 1 × 203/50 → 4-5
#     77s  cpu: 203%/50% 1 10 4 | deploy 5/5
#    123s  cpu: 82%/50% 1 10 5 | deploy 6/7       <- not ceil(5 × 82/50) = 9: Pods still starting/without samples count as 0% on scale-up
#    138s  cpu: 82%/50% 1 10 7 | deploy 7/7
#    184s  cpu: 47%/50% 1 10 7 | deploy 7/7       <- stable: within the 10% tolerance
kubectl get deployment php-apache              # 7/7   (the docs also got 7)
```

## Lab 3 – Stop load → scale down (docs)
```bash
kubectl delete pod load-generator --now
./watch-hpa.sh 420
#      0s  cpu: 45%/50% … 7 | deploy 7/7
#     62s  cpu: 18%/50% … 7
#    123s  cpu: 0%/50%  … 7
#    339s  cpu: 0%/50%  … 7 | deploy 3/3          <- 5 min after the 18% sample: ceil(7 × 18/50) = 3 was still in the window
#    401s  cpu: 0%/50%  … 3 | deploy 1/1
kubectl describe hpa php-apache | sed -n '/^Events/,$p'
#   New size: 4; reason: cpu resource utilization (percentage of request) above target
#   New size: 5; …
#   New size: 7; reason: cpu resource utilization (percentage of request) above target
#   New size: 3; reason: All metrics below target
#   New size: 1; reason: All metrics below target
```

## Lab 4 – autoscaling/v2, conditions (docs)
```bash
kubectl get hpa php-apache -o yaml > /tmp/hpa-v2.yaml     # spec.metrics[0]: Resource cpu Utilization 50 (as in the docs)
kubectl describe hpa php-apache | sed -n '/^Conditions/,/^Events/p'
#   AbleToScale     True    ReadyForNewScale  recommended size matches current size
#   ScalingActive   True    ValidMetricFound  … from cpu resource utilization (percentage of request)
#   ScalingLimited  True    TooFewReplicas    the desired replica count is less than the minimum replica count
#   ScaledToZero    False   NotScaledToZero   the HPA controller did not scale the workload to zero
```

## Lab 5 – Declarative HPA and multiple metrics (docs + fix)
```bash
kubectl delete hpa php-apache
kubectl create -f hpa-php-apache.yaml                      # horizontalpodautoscaler.autoscaling/php-apache created
kubectl apply -f hpa-multiple-metrics.yaml
#   The request is invalid: … parsing time "<some-time>" as "2006-01-02T15:04:05Z07:00": cannot parse "<some-time>" as "2006"
kubectl apply -f hpa-multiple-metrics-fixed.yaml           # (warning about missing last-applied annotation: created with create)
kubectl describe hpa php-apache | sed -n '/^Metrics/,/^Events/p'
#   resource cpu on pods  (as a percentage of request):          0% (1m) / 50%
#   "packets-per-second" on pods:                                <unknown> / 1k
#   "requests-per-second" on Ingress/main-route (target value):  <unknown> / 10k
#   ScalingActive   False   FailedGetPodsMetric  … no custom metrics API (custom.metrics.k8s.io) registered
```
With 2 of 3 metrics invalid, load still scales it up (not from the docs):
```bash
kubectl run load-generator --image=busybox:1.28 --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"
./watch-hpa.sh 120
#     62s  cpu: 213%/50%, <unknown>/1k + 1 | deploy 1/4
#     77s  cpu: 213%/50%, <unknown>/1k + 1 | deploy 5/5
```
Scale-**down** with invalid metrics doesn't happen: the HPA can't be sure the missing metrics are low too.

## Cleanup
```bash
./cleanup.sh
```
