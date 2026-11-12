# API Priority and Fairness – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/flow-control/

> The docs' two FlowSchemas are **verbatim**: [health-for-strangers.yaml](health-for-strangers.yaml) (unauthenticated health checks are exempt) and [list-events-default-service-account.yaml](list-events-default-service-account.yaml) (isolate a noisy `list events` client into catch-all). [00-noisy.yaml](00-noisy.yaml) adds a deliberately tiny priority level for one noisy ServiceAccount, so you can watch APF reject it while everyone else carries on.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **APF** | The API server's concurrency control (on by default, replaces `--max-requests-inflight` limits). Requests are classified, queued fairly, and executed in limited **seats**. |
| **FlowSchema** | Matches requests (subjects + resource/non-resource rules), lowest `matchingPrecedence` wins, and assigns a **priority level**. `distinguisherMethod` (ByUser / ByNamespace) splits flows for fairness. |
| **PriorityLevelConfiguration** | `Exempt`, or `Limited` with `nominalConcurrencyShares` (→ seats out of the server's total), `lendablePercent`/`borrowingLimitPercent`, `limitResponse` `Queue` (shuffle-sharded queues) or `Reject` (HTTP **429** + Retry-After). |
| **Seats** | A request occupies ≥1 seat. Big LISTs cost more, and watches hold seats briefly after their initial events. |
| **Defaults** | Mandatory: `exempt`, `catch-all`. Suggested: `system`, `node-high`, `leader-election`, `workload-high/low`, `global-default`… The API server keeps them maintained unless you take over. |
| **Observability** | Response headers `X-Kubernetes-PF-FlowSchema-UID` / `-PriorityLevel-UID`. Metrics `apiserver_flowcontrol_*`. Debug dump `/debug/api_priority_and_fairness/dump_*`. |

---

## Step 1
```bash
cd concepts/cluster-administration/flow-control
kubectl get prioritylevelconfigurations
#   catch-all Limited 5 Reject | exempt Exempt | global-default 20 Queue | leader-election 10 | node-high 40 | system 30 | workload-high 40 | workload-low 100
kubectl apply -f 00-noisy.yaml -f health-for-strangers.yaml -f list-events-default-service-account.yaml
kubectl get flowschemas -o custom-columns=NAME:.metadata.name,PL:.spec.priorityLevelConfiguration.name,PREC:.spec.matchingPrecedence
#   exempt 1 | probes 2 | noisy-client → tiny 500 | health-for-strangers → exempt 1000 | list-events-default-service-account → catch-all 8000 | catch-all 10000
```

## Lab 1 – Which FlowSchema handled my request?
```bash
S=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}') ; T=$(kubectl create token noisy -n apf-lab)
curl -sk -o /dev/null -D - -H "Authorization: Bearer $T" $S/api/v1/namespaces/apf-lab/pods | grep -i x-kubernetes-pf
#   x-kubernetes-pf-flowschema-uid: 1247ddb7-…     → noisy-client
curl -sk -o /dev/null -D - $S/readyz | grep -i x-kubernetes-pf
#   x-kubernetes-pf-flowschema-uid: 4120eb05-…     → probes (built-in, precedence 2 - beats health-for-strangers' 1000)
```
The docs' `health-for-strangers` is shadowed here: the built-in suggested FlowSchema `probes` already matches `/readyz` at a lower precedence.

## Lab 2 – Overload one client, not the cluster
```bash
kubectl get --raw /metrics | grep 'nominal_limit_seats{priority_level="tiny"'       # 3   (1 share, but rounded up)
seq 400 | xargs -P 100 -I{} curl -sk -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $T" "$S/api/v1/namespaces/apf-lab/pods" | sort | uniq -c
#   400 200        <- empty LISTs finish in ms: 3 seats are plenty
# make each request expensive: 300 ConfigMaps × 20KB in apf-lab, then LIST them 200× with 100 in parallel
#   43 200   157 429         in 0.7s
kubectl get ns default        # 0.18s - the admin (exempt / other levels) doesn't notice
kubectl get --raw /metrics | grep 'rejected_requests_total{.*tiny'
#   apiserver_flowcontrol_rejected_requests_total{flow_schema="noisy-client",priority_level="tiny",reason="concurrency-limit"} 232
kubectl get --raw /debug/api_priority_and_fairness/dump_priority_levels | grep -E '^PriorityLevelName|^tiny'
#   tiny, 0, true, false, 0, 0, 670, 232, 0, 0      (dispatched 670, rejected 232)
```
That's the point of APF: a misbehaving controller gets throttled in **its own** lane instead of taking the API server down for everyone.

---

## Useful commands
```bash
kubectl get flowschemas,prioritylevelconfigurations
kubectl get --raw /debug/api_priority_and_fairness/dump_queues | head
kubectl get --raw /metrics | grep -E 'apiserver_flowcontrol_(current_inqueue_requests|request_wait_duration_seconds_count|rejected_requests_total)'
```

## Cleanup
```bash
./cleanup.sh
```
