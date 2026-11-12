# Pod Scheduling Readiness – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/pod-scheduling-readiness/

> The docs' two Pods are **verbatim**: [pod-with-scheduling-gates.yaml](pod-with-scheduling-gates.yaml) and [pod-without-scheduling-gates.yaml](pod-without-scheduling-gates.yaml) (both named `test-pod`: applying the second removes the gates). Namespace `gate-demo`. [metrics-reader.yaml](metrics-reader.yaml) lets you read the scheduler's metrics.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **schedulingGates** | A list of names in `spec`. While non-empty, the scheduler **ignores** the Pod: status `SchedulingGated`, condition `PodScheduled=False, reason SchedulingGated`. |
| **Who adds/removes** | Gates can only be set at **creation**. Afterwards they can only be **removed** (by controllers: quota managers, provisioners, Kueue…). |
| **Why** | Pods that can't be scheduled yet (waiting for quota, data, a node pool) would otherwise churn the scheduler queue forever. |
| **Observability** | `scheduler_pending_pods{queue="gated"}`. |
| **Mutable directives** | While gated you may only **tighten**: add `nodeSelector` keys, set node affinity if empty, add expressions; preferred terms are freely editable. After scheduling, none of it can change. |

---

## Lab 1 – A gated Pod (docs)
```bash
cd concepts/scheduling-eviction/pod-scheduling-readiness
kubectl create ns gate-demo ; N="-n gate-demo"
kubectl apply $N -f pod-with-scheduling-gates.yaml
kubectl get pod test-pod $N                    # test-pod   0/1   SchedulingGated   0   0s
kubectl get pod test-pod $N -o jsonpath='{.spec.schedulingGates}'
#   [{"name":"example.com/foo"},{"name":"example.com/bar"}]
kubectl get pod test-pod $N -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{end}'
#   PodScheduled=False SchedulingGated: Scheduling is blocked due to non-empty scheduling gates
```

## Lab 2 – The gated queue metric
```bash
kubectl apply -f metrics-reader.yaml
T=$(kubectl create token metrics-reader -n gate-demo)
minikube ssh -- "curl -sk -H 'Authorization: Bearer $T' https://127.0.0.1:10259/metrics | grep '^scheduler_pending_pods'"
#   scheduler_pending_pods{queue="gated"} 1          <- (active/backoff/unschedulable 0)
```

## Lab 3 – Tightening while gated
```bash
kubectl patch pod test-pod $N -p '{"spec":{"nodeSelector":{"kubernetes.io/os":"linux"}}}'          # OK: addition
kubectl patch pod test-pod $N -p '{"spec":{"nodeSelector":{"kubernetes.io/os":"windows"}}}'
#   spec.nodeSelector: Invalid value: ...: only additions to spec.nodeSelector are allowed (no mutations or deletions)
kubectl patch pod test-pod $N -p '{"spec":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"type","operator":"DoesNotExist"}]}]}}}}}'
#   OK: affinity was empty                                           (and it keeps fake nodes out)
```

## Lab 4 – Removing gates
```bash
kubectl patch pod test-pod $N --type=json -p '[{"op":"remove","path":"/spec/schedulingGates/0"}]'
kubectl get pod test-pod $N                    # still SchedulingGated - example.com/bar remains
kubectl patch pod test-pod $N --type=json -p '[{"op":"add","path":"/spec/schedulingGates/-","value":{"name":"example.com/new"}}]'
#   spec.schedulingGates[1].name: Forbidden: only deletion is allowed, but found new scheduling gate 'example.com/new'
kubectl apply $N -f pod-without-scheduling-gates.yaml     # docs: same Pod without gates → kubectl apply removes them
kubectl get pod test-pod $N -o wide             # Running   minikube
kubectl patch pod test-pod $N -p '{"spec":{"nodeSelector":{"extra":"x"}}}'
#   Forbidden: pod updates may not change fields other than ...    <- once scheduled, directives are frozen
```

---

## Useful commands
```bash
kubectl get pods -A --field-selector status.phase=Pending -o custom-columns=NAME:.metadata.name,GATES:.spec.schedulingGates[*].name
kubectl patch pod <p> --type=json -p '[{"op":"remove","path":"/spec/schedulingGates"}]'      # remove all gates
```

## Cleanup
```bash
./cleanup.sh
```
