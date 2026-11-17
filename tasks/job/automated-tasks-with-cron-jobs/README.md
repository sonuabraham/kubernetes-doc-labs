# Running Automated Tasks with a CronJob – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/

> Runs on the default **minikube** cluster, `default` namespace. File: [cronjob.yaml](cronjob.yaml) (docs, **verbatim**). Takes ~5 minutes of wall-clock time.
> Concept lab with more detail (schedules, time zones, concurrency, deadlines): [concepts/workloads/controllers/cron-jobs](../../../concepts/workloads/controllers/cron-jobs/).
>
> **Found:** the sample output shows `*/1 * * * *`, but the manifest says `* * * * *` (same meaning). Job names aren't random: the suffix is the
> scheduled time in **minutes since the Unix epoch** (`hello-29915214`). A manual `kubectl create job --from=cronjob/…` Job counts toward the
> history limit and was cleaned up along with the scheduled ones.

## Key ideas (read first)

| Field / behaviour | Meaning |
|---|---|
| `schedule` | cron syntax, controller's time zone unless `timeZone` is set |
| Job name | `<cronjob>-<scheduled time in minutes since epoch>`; annotation `batch.kubernetes.io/cronjob-scheduled-timestamp` |
| History | `successfulJobsHistoryLimit: 3`, `failedJobsHistoryLimit: 1` (defaults); older Jobs + Pods are deleted |
| `concurrencyPolicy` | `Allow` (default), `Forbid`, `Replace` |
| `suspend: true` | no new runs; running Jobs continue |
| Delete CronJob | Jobs and Pods are owned by it → garbage-collected |

---

## Lab 1 – Create and watch (docs)
```bash
cd tasks/job/automated-tasks-with-cron-jobs
kubectl create -f cronjob.yaml                 # cronjob.batch/hello created
kubectl get cronjob hello
#   NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
#   hello   * * * * *   <none>     False     0        <none>          0s
kubectl get jobs --watch                       # Ctrl+C after the first run (at the next full minute)
#   hello-29915214   Complete   1/1   2s   3s
echo $(( $(date +%s) / 60 ))                   # 29915214   <- the name suffix
kubectl get cronjob hello                      # LAST SCHEDULE 3s
pods=$(kubectl get pods --selector=job-name=hello-29915214 --output=jsonpath={.items[*].metadata.name})
kubectl logs $pods
#   Tue Nov 17 10:54:00 UTC 2026
#   Hello from the Kubernetes cluster
kubectl get job hello-29915214 -o jsonpath='{.metadata.annotations}'
#   {"batch.kubernetes.io/cronjob-scheduled-timestamp":"2026-11-17T10:54:00Z"}
```

## Lab 2 – Manual run, history, suspend (not from the docs)
```bash
kubectl create job hello-manual --from=cronjob/hello
kubectl get job hello-manual -o jsonpath='{.metadata.annotations} owner={.metadata.ownerReferences[0].name}'
#   {"cronjob.kubernetes.io/instantiate":"manual"} owner=hello
# … wait ~3 minutes …
kubectl get jobs
#   hello-29915215   Complete   1/1   3s   2m10s
#   hello-29915216   Complete   1/1   3s   70s
#   hello-29915217   Complete   1/1   3s   10s      <- only 3 kept; hello-29915214 AND hello-manual were removed
kubectl patch cronjob hello -p '{"spec":{"suspend":true}}'
kubectl get cronjob hello                      # SUSPEND True — no more runs
```

## Lab 3 – Delete (docs)
```bash
kubectl delete cronjob hello
kubectl get jobs,pods                          # No resources found   <- removed with it
```

## Cleanup
```bash
./cleanup.sh
```
