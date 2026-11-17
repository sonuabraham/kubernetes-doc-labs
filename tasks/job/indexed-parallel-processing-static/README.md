# Indexed Job for Parallel Processing with Static Work Assignment – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/job/indexed-parallel-processing-static/

> Runs on the default **minikube** cluster, `default` namespace. Files (docs, **verbatim**): [indexed-job.yaml](indexed-job.yaml)
> (index → word via `$JOB_COMPLETION_INDEX` in an init container), [indexed-job-vol.yaml](indexed-job-vol.yaml) (index as a downward-API file).
> Not from the docs: [indexed-job-failing-index.yaml](indexed-job-failing-index.yaml).
>
> **Notes:** the page says the variable is linked to the "annotation". The injected env var now reads the **label**
> `batch.kubernetes.io/job-completion-index` (the annotation exists too). `indexed-job-vol.yaml` only reverses the index itself
> (`0` → `0`), so its output is the index.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `completionMode: Indexed` | `completions: N` → indexes `0..N-1`; one successful Pod per index |
| Where the index is | env `JOB_COMPLETION_INDEX`, annotation/label `batch.kubernetes.io/job-completion-index`, Pod hostname `<job>-<index>` |
| Status | `completedIndexes` (`0-4`), with `backoffLimitPerIndex` also `failedIndexes` |
| Static assignment | no queue: each index maps to its work item (here `items[$JOB_COMPLETION_INDEX]`) |

---

## Lab 1 – Env var + init container (docs)
```bash
cd tasks/job/indexed-parallel-processing-static
kubectl apply -f indexed-job.yaml
kubectl describe jobs/indexed-job | grep -E 'Parallelism|Completions|Completion Mode|Pods Statuses|Completed Indexes'
#   Parallelism:        3
#   Completions:        5
#   Completion Mode:    Indexed
#   Pods Statuses:      3 Active (1 Ready) / 1 Succeeded / 0 Failed
#   Completed Indexes:  0
kubectl wait --for=condition=complete --timeout=300s job/indexed-job
kubectl describe jobs/indexed-job | grep 'Completed Indexes'      # 0-4
for p in $(kubectl get pods -l job-name=indexed-job -o name | sort); do echo "$p -> $(kubectl logs $p -c worker)"; done
#   pod/indexed-job-0-jtt8x -> oof
#   pod/indexed-job-1-m64dl -> rab
#   pod/indexed-job-2-8jf2x -> zab
#   pod/indexed-job-3-wxxgf -> xuq        <- the docs' sample "xuq" = index 3
#   pod/indexed-job-4-cwdz8 -> zyx
kubectl get pod -l batch.kubernetes.io/job-completion-index=0,job-name=indexed-job -o jsonpath='{.items[0].spec.hostname} {.items[0].spec.containers[0].env}'
#   indexed-job-0 [{"name":"JOB_COMPLETION_INDEX","valueFrom":{"fieldRef":{…"fieldPath":"metadata.labels['batch.kubernetes.io/job-completion-index']"}}}]
kubectl delete job indexed-job
```

## Lab 2 – Downward API volume (docs)
```bash
kubectl apply -f indexed-job-vol.yaml
kubectl wait --for=condition=complete --timeout=300s job/indexed-job
for p in $(kubectl get pods -l job-name=indexed-job -o name | sort); do echo "$p -> [$(kubectl logs $p)]"; done
#   pod/indexed-job-0-kvd9x -> [0]   …   pod/indexed-job-4-hlpf9 -> [4]
kubectl delete job indexed-job
```

## Lab 3 – One index keeps failing (not from the docs)
```bash
kubectl apply -f indexed-job-failing-index.yaml
kubectl wait --for=condition=failed --timeout=180s job/indexed-job-fail
kubectl get job indexed-job-fail -o jsonpath='completed={.status.completedIndexes} failed={.status.failedIndexes}'
#   completed=0,1,3,4 failed=2
kubectl get pods -l job-name=indexed-job-fail --sort-by=.metadata.name
#   indexed-job-fail-2-…   Error   (×2: first try + 1 retry from backoffLimitPerIndex)
#   others Completed      <- Job condition Failed, reason FailedIndexes
```
More on per-index retries: [concepts/workloads/controllers/job](../../../concepts/workloads/controllers/job/).

## Cleanup
```bash
./cleanup.sh
```
