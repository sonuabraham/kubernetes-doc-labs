# Jobs – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/controllers/job/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Job** | Creates Pods and retries them until a number of them **complete successfully**. Then the Job is done. Deleting it deletes its Pods. `suspend` stops its active Pods. |
| **Patterns** | Non-parallel (1 pod), **fixed completion count** (`completions`), **work queue** (`parallelism`, no `completions`). |
| **completionMode: Indexed** | Each Pod gets an index 0…N-1 (`JOB_COMPLETION_INDEX`, the hostname `<job>-<index>`, an annotation). One success per index. |
| **Pod template** | `restartPolicy` must be `Never` or `OnFailure`. |
| **backoffLimit** | Retries before the Job fails (default 6, exponential back-off 10s, 20s… capped at 6 min). |
| **backoffLimitPerIndex / maxFailedIndexes** | (stable) A retry budget **per index** for Indexed Jobs. The other indexes keep running. |
| **podFailurePolicy** | Rules on exit codes or pod conditions: `FailJob`, `Ignore` (doesn't count, e.g. `DisruptionTarget`), `Count`, `FailIndex`. |
| **successPolicy** | Declare success early: `succeededIndexes` / `succeededCount`. Remaining pods are terminated. |
| **activeDeadlineSeconds** | Wall-clock limit for the **whole Job** (from start, including image pulls). It beats backoffLimit. |
| **Conditions** | `FailureTarget` / `SuccessCriteriaMet` first (pods still terminating), then `Failed` / `Complete`. |
| **ttlSecondsAfterFinished** | Auto-delete a finished Job (see `../ttlafterfinished`). |
| **suspend** | `true` = no pods (running ones are terminated). Lets queueing systems decide when to start. Scheduling directives can be changed while suspended. |
| **podReplacementPolicy** | `TerminatingOrFailed` (default) or `Failed`: create a replacement only once the old pod is **fully** failed. `status.terminating` counts the pods in between. |
| **Elastic Indexed Jobs** | Change `completions` **together with** `parallelism` to scale an Indexed Job. |
| **Tracking finalizer** | `batch.kubernetes.io/job-tracking` on every pod (see `../../../overview/working-with-objects/finalizers`). |
| **managedBy** | Delegate a Job to an external controller. |
| **Workload integration** | `.spec.scheduling` with gang scheduling (`WorkloadWithJob`, alpha). See `../../workload-api`. |

## The demo app
The docs manifests are **verbatim**:

| File | What |
|---|---|
| [job.yaml](job.yaml) | `pi`: 2000 digits of π with perl |
| [job-backoff-limit-per-index-example.yaml](job-backoff-limit-per-index-example.yaml) | 10 indexes, even ones fail |
| [job-pod-failure-policy-example.yaml](job-pod-failure-policy-example.yaml) | exit 42 → `FailJob`, `DisruptionTarget` → `Ignore` |
| [job-success-policy.yaml](job-success-policy.yaml) | only index 2 succeeds, which is enough |
| [job-pi-with-timeout.yaml](job-pi-with-timeout.yaml), [job-pi-with-ttl.yaml](job-pi-with-ttl.yaml) | `activeDeadlineSeconds: 100`, `ttlSecondsAfterFinished: 100` |
| [job-batch-processor.yaml](job-batch-processor.yaml) | Basic scheduling example (namespace `batch`, placeholder image `processor-image:v1`) |
| [job-gang-distributed-training.yaml](job-gang-distributed-training.yaml) | Gang-scheduling example (needs alpha gates, see `../../workload-api`) |
| `*-excerpt.yaml` | status/spec fragments from the page, for reference |

Extra: [01-indexed-parallel.yaml](01-indexed-parallel.yaml), [02-suspend.yaml](02-suspend.yaml) (the docs' suspended `myjob`, filled in), [03-pod-replacement-policy.yaml](03-pod-replacement-policy.yaml).

---

## Step 1 – Start them all (the python images are big, so give it a few minutes)
```bash
cd concepts/workloads/controllers/job
kubectl apply -f 00-namespace.yaml
kubectl apply -n job-demo -f job.yaml -f job-backoff-limit-per-index-example.yaml -f job-pod-failure-policy-example.yaml \
  -f job-success-policy.yaml -f job-pi-with-timeout.yaml -f job-pi-with-ttl.yaml
kubectl apply -f job-batch-processor.yaml -f 01-indexed-parallel.yaml -f 02-suspend.yaml
kubectl get jobs -A -w
```

## Lab 1 – The docs' pi Job
```bash
kubectl wait --for=condition=Complete job/pi -n job-demo --timeout=300s
kubectl describe job pi -n job-demo | grep -E 'Pods Statuses|Completions'
kubectl logs job/pi -n job-demo | cut -c1-40          # 3.14159265358979323846264338327950288419
kubectl get pods -n job-demo -l batch.kubernetes.io/job-name=pi --show-labels
```

## Lab 2 – Parallel + Indexed
```bash
kubectl logs -n job-demo -l job-name=indexed --prefix=false | sort
#   processing shard 0 on indexed-0  ...  processing shard 4 on indexed-4     <- index in env AND hostname
kubectl get job indexed -n job-demo -o jsonpath='{.status.completedIndexes}{"\n"}'     # 0-4
```

## Lab 3 – Pod failure policy (docs)
```bash
kubectl wait --for=condition=Failed job/job-pod-failure-policy-example -n job-demo --timeout=300s
kubectl get job job-pod-failure-policy-example -n job-demo -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
#   FailureTarget=True PodFailurePolicy: Container main ... failed with exit code 42 matching FailJob rule at index 0
#   Failed=True PodFailurePolicy: ...
```
It failed after the **first** pod (exit 42), without burning through `backoffLimit: 6`. A bug isn't worth retrying.

## Lab 4 – Backoff limit per index (docs)
```bash
kubectl wait --for=condition=Failed job/job-backoff-limit-per-index-example -n job-demo --timeout=400s
kubectl get job job-backoff-limit-per-index-example -n job-demo -o jsonpath='completed={.status.completedIndexes} failed={.status.failedIndexes} succeeded={.status.succeeded} failedPods={.status.failed}{"\n"}'
#   completed=1,3,5,7,9 failed=0,2,4,6,8 succeeded=5 failedPods=10      <- exactly the docs' status excerpt
```
Every index ran. Each even index failed twice (1 retry), and the Job still finished all the odd ones.

## Lab 5 – Success policy (docs)
```bash
kubectl wait --for=condition=Complete job/job-success -n job-demo --timeout=400s
kubectl get job job-success -n job-demo -o jsonpath='succeeded={.status.succeeded} completedIndexes={.status.completedIndexes} {range .status.conditions[*]}{.type}={.reason} {end}{"\n"}'
#   succeeded=1 completedIndexes=2 SuccessCriteriaMet=SuccessPolicy Complete=SuccessPolicy
```
9 of 10 pods failed, yet the Job is **Complete**: index 2 is in `succeededIndexes: 0,2-3` and `succeededCount: 1` was reached.

## Lab 6 – Suspend
```bash
kubectl get pods -n job-demo -l job-name=myjob          # none
kubectl get job myjob -n job-demo -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'    # Suspended=True
kubectl patch job myjob -n job-demo --type=strategic -p '{"spec":{"suspend":false}}'
kubectl wait --for=condition=Complete job/myjob -n job-demo
```

## Lab 7 – podReplacementPolicy: Failed
```bash
kubectl apply -f 03-pod-replacement-policy.yaml ; kubectl wait --for=condition=Ready pod -l job-name=new -n job-demo
kubectl delete pod -l job-name=new -n job-demo --wait=false ; sleep 4
kubectl get job new -n job-demo -o jsonpath='active={.status.active} terminating={.status.terminating}{"\n"}'
#   active= terminating=1       <- like the docs' status excerpt; NO replacement yet (the pod needs ~15s to stop)
kubectl get pods -n job-demo -l job-name=new -w           # replacement appears only after the old pod reached Failed
```

## Lab 8 – Deadlines and TTL
```bash
kubectl get job pi-with-timeout -n job-demo -o jsonpath='{range .status.conditions[*]}{.type}={.reason}: {.message}{"\n"}{end}'
kubectl get events -n job-demo | grep pi-with-timeout | grep Pulled
```
In our run `pi-with-timeout` **failed** with `DeadlineExceeded`:
```
Pulled  Successfully pulled image "perl:5.34.0" in 1.435s (2m30.828s including waiting)
```
The pull itself took 1.4s, but it **waited 2.5 minutes** behind the big python images: the kubelet pulls one image at a time by default (`serializeImagePulls`, see `../../../containers/images`). `activeDeadlineSeconds` counts from the Job's start, pull time included. Run it alone and it completes.
```bash
kubectl get job pi-with-ttl -n job-demo        # NotFound ~100s after it finished (TTL controller)
```

## Lab 9 – Elastic Indexed Job
```bash
kubectl create job elastic -n job-demo --image=busybox:1.36 --dry-run=client -o json -- sleep 30 \
  | jq '.spec += {"completionMode":"Indexed","completions":2,"parallelism":2}' | kubectl apply -f -
kubectl patch job elastic -n job-demo -p '{"spec":{"completions":4,"parallelism":4}}'      # ok - scaled to 4 indexes
kubectl patch job elastic -n job-demo -p '{"spec":{"completions":5,"parallelism":4}}'
#   spec.completions: Invalid value: 5: can only be modified in tandem with spec.parallelism
```

## Lab 10 – Placeholder images
```bash
kubectl get pods -n batch                     # batch-processor-*  ImagePullBackOff - processor-image:v1 is a placeholder
```
It's a shape example for Basic scheduling. The gang version ([job-gang-distributed-training.yaml](job-gang-distributed-training.yaml)) is run in `../../workload-api`.

---

## Useful commands
```bash
kubectl create job <name> --image=<img> -- <cmd>
kubectl get job <j> -o jsonpath='{.status}' | jq .
kubectl logs job/<j> ; kubectl get pods -l batch.kubernetes.io/job-name=<j>
kubectl wait --for=condition=Complete|Failed job/<j>
```

## Cleanup
```bash
./cleanup.sh
```
