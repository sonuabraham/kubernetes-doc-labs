# Handling retriable and non-retriable pod failures with Pod failure policy – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/job/pod-failure-policy/

> Runs on the default **minikube** cluster, `default` namespace. Files (docs, **verbatim**):
> [job-pod-failure-policy-failjob.yaml](job-pod-failure-policy-failjob.yaml), [job-pod-failure-policy-ignore.yaml](job-pod-failure-policy-ignore.yaml),
> [job-pod-failure-policy-config-issue.yaml](job-pod-failure-policy-config-issue.yaml),
> [job-backoff-limit-per-index-failindex.yaml](job-backoff-limit-per-index-failindex.yaml).
> Not from the docs: [evict.sh](evict.sh) (Eviction API for one Pod, from the [configure-pdb](../../run-application/configure-pdb/) lab).
>
> **Adapted:** scenario 2 drains the node. On single-node minikube that would evict CoreDNS and everything else, so Lab 2 evicts just the
> Job's Pod with the Eviction API. The Pod gets the same `DisruptionTarget` condition (`EvictionByEvictionAPI`).

## Key ideas (read first)

| Rule action | Effect |
|---|---|
| `FailJob` | fail the whole Job at once (no more retries) |
| `Ignore` | the failure isn't counted against `backoffLimit`; the Pod is replaced |
| `Count` | normal behaviour (counts toward `backoffLimit`) |
| `FailIndex` | with `backoffLimitPerIndex`: fail only this index, no retry |
| Match on | `onExitCodes` (container + operator + values) or `onPodConditions` (e.g. `DisruptionTarget`, custom `ConfigIssue`) |
| Requires | `restartPolicy: Never` |

---

## Lab 1 – Exit code 42 = bug → FailJob (docs)
```bash
cd tasks/job/pod-failure-policy
kubectl create -f job-pod-failure-policy-failjob.yaml
kubectl wait --for=condition=failed job/job-pod-failure-policy-failjob --timeout=120s     # after ~33 s
kubectl get jobs -l job-name=job-pod-failure-policy-failjob -o yaml     # status.conditions:
#   FailureTarget PodFailurePolicy: Container main for pod default/job-pod-failure-policy-failjob-bcdzd failed with exit code 42 matching FailJob rule at index 0
#   Failed        PodFailurePolicy: (same message)
#   failed: 2                    <- both parallel Pods, no retries (without the policy: 6 retries with backoff, 9+ min)
kubectl delete jobs/job-pod-failure-policy-failjob
```

## Lab 2 – Ignore disruptions (docs, adapted)
```bash
kubectl create -f job-pod-failure-policy-ignore.yaml          # backoffLimit: 0 !
P=$(kubectl get pods -l job-name=job-pod-failure-policy-ignore -o jsonpath='{.items[0].metadata.name}')
./evict.sh $P                                                 # instead of kubectl drain
kubectl get pod $P -o json | jq -r '.status.conditions[] | select(.type=="DisruptionTarget") | "\(.reason): \(.message)"'
#   EvictionByEvictionAPI: Eviction API: evicting
kubectl get job job-pod-failure-policy-ignore -o jsonpath='failed={.status.failed}'    # failed=   (not counted)
kubectl wait --for=condition=complete job/job-pod-failure-policy-ignore --timeout=300s    # ~3.5 min (90 s Pods, 2 at a time, + replacement)
kubectl get job job-pod-failure-policy-ignore -o jsonpath='failed={.status.failed} succeeded={.status.succeeded}'
#   failed= succeeded=4
kubectl delete jobs/job-pod-failure-policy-ignore
```
Comparison (not from the docs): the same Job **without** `podFailurePolicy`:
```bash
sed -e 's/name: job-pod-failure-policy-ignore/name: job-no-policy/' -e '/podFailurePolicy:/,$d' job-pod-failure-policy-ignore.yaml | kubectl create -f -
./evict.sh $(kubectl get pods -l job-name=job-no-policy -o jsonpath='{.items[0].metadata.name}')
kubectl get job job-no-policy -o jsonpath='{.status.conditions[?(@.type=="Failed")].reason}'     # BackoffLimitExceeded
kubectl delete job job-no-policy
```
The evicted bash Pod takes ~30 s to stop: bash as PID 1 ignores SIGTERM, so it waits out the grace period.

## Lab 3 – Custom Pod condition (docs)
```bash
kubectl create -f job-pod-failure-policy-config-issue.yaml
kubectl get pods -l job-name=job-pod-failure-policy-config-issue -o jsonpath='{range .items[*]}{.metadata.name} {.status.phase} {.status.containerStatuses[0].state.waiting.reason}{"\n"}{end}'
#   …-jx4cn Pending ErrImagePull
cat <<EOF > patch.yaml
status:
  conditions:
  - type: ConfigIssue
    status: "True"
    reason: "NonExistingImage"
    lastTransitionTime: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF
podName=$(kubectl get pods -l job-name=job-pod-failure-policy-config-issue -o jsonpath='{.items[0].metadata.name}')
kubectl patch pod $podName --subresource=status --patch-file=patch.yaml       # pod/… patched
kubectl delete pods/$podName                                                  # Pending → Failed (keeps the condition)
kubectl get jobs -l job-name=job-pod-failure-policy-config-issue -o yaml
#   Failed PodFailurePolicy: Pod default/job-pod-failure-policy-config-issue-jx4cn has condition ConfigIssue matching FailJob rule at index 0
kubectl delete jobs/job-pod-failure-policy-config-issue
```

## Lab 4 – FailIndex with backoffLimitPerIndex (docs)
```bash
kubectl create -f job-backoff-limit-per-index-failindex.yaml
kubectl get pods -l job-name=job-backoff-limit-per-index-failindex --sort-by=.metadata.name
#   …-0-tfv29   Error       <- index 0: exit 1, retried once
#   …-0-z6q59   Error
#   …-1-bnnzd   Error       <- index 1: exit 42 → FailIndex, no retry
#   …-2-wh68p   Completed
#   …-3-m4nxd   Completed
kubectl get job job-backoff-limit-per-index-failindex -o jsonpath='failedIndexes={.status.failedIndexes} failed={.status.failed}'
#   failedIndexes=0,1 failed=3                       (condition Failed, reason FailedIndexes)
kubectl delete jobs/job-backoff-limit-per-index-failindex
```

## Cleanup
```bash
./cleanup.sh
```
