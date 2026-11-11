# Automatic Cleanup for Finished Jobs – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/controllers/ttlafterfinished/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **TTL-after-finished controller** | Deletes a Job (cascading: its Pods too) `.spec.ttlSecondsAfterFinished` seconds after it **finished** (`Complete` or `Failed`). Stable since 1.23. **Jobs only.** |
| **Why keep finished Jobs at all?** | So you can see whether they succeeded. The TTL bounds how long they stay. |
| **Setting it** | In the manifest, **later** on an already-finished Job, or by a mutating webhook (cluster-wide policy) or your own controller. |
| **Lifecycle guarantees** | Deletion respects **finalizers**. TTL starts the deletion, and finalizers can still hold it. |
| **Caveats** | Extending the TTL **after** it expired isn't guaranteed to save the Job. The controller uses timestamps, so it's sensitive to **clock skew**. |

## The demo app
[00-jobs.yaml](00-jobs.yaml), namespace `ttl-demo`:

| Job | Setup |
|---|---|
| `quick-ttl` | `ttlSecondsAfterFinished: 20` |
| `no-ttl` | no TTL (you add one in Lab 2) |
| `held` | TTL 5 **plus** a finalizer `example.com/archive-logs-first` |

---

## Lab 1 – TTL in the manifest
```bash
cd concepts/workloads/controllers/ttlafterfinished
kubectl apply -f 00-jobs.yaml ; sleep 10
kubectl get jobs,pods -n ttl-demo              # all three Complete
sleep 25
kubectl get jobs -n ttl-demo                   # quick-ttl GONE (and its pod) ~20s after completion
```

## Lab 2 – Add a TTL to a Job that already finished
```bash
kubectl patch job no-ttl -n ttl-demo -p '{"spec":{"ttlSecondsAfterFinished":5}}'
sleep 10 ; kubectl get job no-ttl -n ttl-demo  # NotFound - it finished long ago, so 5s had already passed
```
This is how you clean up old Jobs in bulk:
`kubectl get jobs -o name | xargs -I{} kubectl patch {} -p '{"spec":{"ttlSecondsAfterFinished":0}}'`.

## Lab 3 – Finalizers still apply
```bash
kubectl get job held -n ttl-demo -o jsonpath='deletionTimestamp={.metadata.deletionTimestamp} finalizers={.metadata.finalizers}{"\n"}'
#   deletionTimestamp=2026-…  finalizers=["example.com/archive-logs-first"]    <- TTL fired, the Job is only being HELD
kubectl patch job held -n ttl-demo --type=merge -p '{"metadata":{"finalizers":null}}'     # "archiving done"
kubectl get job held -n ttl-demo               # NotFound
```

## Lab 4 – Where it shows up elsewhere
- CronJobs use **history limits** rather than a TTL ([../cron-jobs](../cron-jobs/)).
- Many charts set `ttlSecondsAfterFinished` on hook Jobs so `helm upgrade` can recreate them.

---

## Useful commands
```bash
kubectl get jobs -o custom-columns=NAME:.metadata.name,TTL:.spec.ttlSecondsAfterFinished,DONE:.status.completionTime
kubectl patch job <j> -p '{"spec":{"ttlSecondsAfterFinished":N}}'
```

## Cleanup
```bash
./cleanup.sh       # removes the finalizer if still set, deletes the namespace
```
