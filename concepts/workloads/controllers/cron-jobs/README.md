# CronJob – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **CronJob** | Creates a **Job** on a repeating schedule (cron format). Stable since 1.21. Name ≤ 52 characters (the controller appends 11 characters). |
| **schedule** | `minute hour day-of-month month day-of-week`, plus macros like `@hourly`, `@daily`, and `*/5`. |
| **timeZone** | `.spec.timeZone: "Asia/Tokyo"` (stable 1.27). Without it, the kube-controller-manager's time zone applies. `TZ=`/`CRON_TZ=` inside `schedule` is **rejected**. |
| **startingDeadlineSeconds** | How late a missed run may still start. If more than 100 runs are missed, the CronJob stops scheduling and logs an error. |
| **concurrencyPolicy** | `Allow` (default), `Forbid` (skip if the previous Job is still running), `Replace` (delete the running Job, start a new one). |
| **suspend** | Pauses future runs (missed ones count as missed). Running Jobs aren't affected. |
| **History** | `successfulJobsHistoryLimit` (3), `failedJobsHistoryLimit` (1). Older Jobs are deleted. |
| **Job creation** | "About once" per run: in rare cases 0 or 2 Jobs, so make Jobs **idempotent**. |
| **Modifying** | Changes apply to **future** Jobs only. |

## The demo app
[cronjob.yaml](cronjob.yaml) is the docs manifest **verbatim**: `hello`, every minute, prints the date. Extra in namespace `cron-demo`: [01-concurrency.yaml](01-concurrency.yaml) (90s jobs every minute with `Forbid` / `Replace`), [02-timezone-history.yaml](02-timezone-history.yaml) (Tokyo time zone, history limits, starting deadline) and [03-tz-in-schedule.yaml](03-tz-in-schedule.yaml) (invalid).

---

## Lab 1 – The docs' hello CronJob
```bash
cd concepts/workloads/controllers/cron-jobs
kubectl apply -f 00-namespace.yaml
kubectl apply -f cronjob.yaml -n cron-demo
kubectl get cronjob hello -n cron-demo -w            # LAST SCHEDULE fills in every minute
kubectl get jobs -n cron-demo --watch                # hello-29907193, hello-29907194, ... (suffix = scheduled minute)
kubectl logs job/$(kubectl get jobs -n cron-demo -o name | grep hello | tail -1 | cut -d/ -f2) -n cron-demo
#   Wed Nov 11 21:15:00 UTC 2026
#   Hello from the Kubernetes cluster
```

## Lab 2 – Run it now (manual trigger) and history limits
```bash
kubectl create job manual-hello --from=cronjob/hello -n cron-demo
kubectl get jobs -n cron-demo
```
After a few minutes, only the newest **3** successful Jobs remain (default `successfulJobsHistoryLimit`), and `manual-hello` is pruned too, because it's owned by the CronJob.

## Lab 3 – Concurrency policies
```bash
kubectl apply -f 01-concurrency.yaml
sleep 150
kubectl get jobs -n cron-demo -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,START:.status.startTime | grep slow
kubectl get events -n cron-demo --field-selector reason=JobAlreadyActive -o custom-columns=M:.message
#   Not starting job because prior execution is running and concurrency policy is Forbid
kubectl get events -n cron-demo --field-selector involvedObject.name=slow-replace -o custom-columns=R:.reason,M:.message
#   SuccessfulCreate  Created job slow-replace-29907193
#   SuccessfulDelete  Deleted job slow-replace-29907193      <- killed after 60s to make room
#   SuccessfulCreate  Created job slow-replace-29907194 ...
```
In our run, `slow-forbid-29907194` started at **21:14:33**, not 21:14:00. The 21:14 run was held back, then started as soon as the previous Job finished, still within the scheduling window. With `Forbid`, no two of these Jobs ever run at once. With `Replace`, a Job never gets to finish its 90s.

## Lab 4 – Time zones and starting deadline
```bash
kubectl apply -f 02-timezone-history.yaml
kubectl get cronjob tokyo-report -n cron-demo          # SCHEDULE 30 9 * * 1-5   TIMEZONE Asia/Tokyo
TZ=Asia/Tokyo date                                     # when will it fire for you?
kubectl apply -f 03-tz-in-schedule.yaml
#   spec.schedule: Invalid value: "TZ=Europe/Berlin 0 6 * * *": cannot use TZ or CRON_TZ in schedule, use timeZone field instead
```

## Lab 5 – Suspend
```bash
kubectl patch cronjob hello -n cron-demo -p '{"spec":{"suspend":true}}'
kubectl get cronjob hello -n cron-demo          # SUSPEND True - no new Jobs (missed runs count as missed)
kubectl patch cronjob hello -n cron-demo -p '{"spec":{"suspend":false}}'
```

---

## Useful commands
```bash
kubectl get cronjob ; kubectl get jobs --watch
kubectl create job <name> --from=cronjob/<cj>
kubectl create cronjob <name> --image=busybox --schedule="*/5 * * * *" -- date
kubectl patch cronjob <cj> -p '{"spec":{"suspend":true}}'
```

## Cleanup
```bash
./cleanup.sh
```
