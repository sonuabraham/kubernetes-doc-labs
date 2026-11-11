# Scheduling Building Block APIs and the workloadbuilder Library – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/workload-api/workloadbuilder/

> This page is for **controller authors** (Go). There's nothing to install. The lab shows the building blocks through the one built-in consumer, the **Job** API (`.spec.scheduling`), on the `wl-lab` profile.

## Key ideas (read first)

| Building block (`scheduling.k8s.io/v1alpha3` Go types) | In a Job | Notes |
|---|---|---|
| `WorkloadPodGroupSchedulingPolicy` | `spec.scheduling.schedulingPolicy` | `basic` / `gang`. `gang.minCount` is **optional**: the controller defaults it (Job → parallelism). |
| `WorkloadPodGroupSchedulingConstraints` | `spec.scheduling.schedulingConstraints` | `topology: [{key}]`, at most one, immutable. |
| `WorkloadPodGroupDisruptionMode` | `spec.scheduling.disruptionMode` | `single` / `all`. `all` + `basic` is rejected. |
| `WorkloadPodGroupResourceClaim` | `spec.scheduling.resourceClaims` | DRA claims **shared** by the whole group (≤ 4). |
| `WorkloadCompositePodGroup…` | — | The same blocks for groups of groups (`minGroupCount`), e.g. a JobSet orchestrating Jobs. |
| **workloadbuilder** library | — | Compiles a controller's embedded blocks into `Workload` + `PodGroup` (+ `CompositePodGroup`) objects and validates them, so every controller behaves alike. |

## Lab 1 – The blocks as the Job API exposes them
```bash
kubectl explain job.spec.scheduling --recursive
#   disruptionMode {all, single} / resourceClaims [{name, resourceClaimName, resourceClaimTemplateName}]
#   schedulingConstraints {topology [{key}]} / schedulingPolicy {basic, gang {minCount}}
```

## Lab 2 – What the library compiles a Job into
```bash
kubectl create namespace builder-demo
kubectl create job compiled -n builder-demo --image=busybox:1.36 --dry-run=client -o json -- sleep 30 \
  | jq '.spec += {"parallelism":3,"completions":3,"completionMode":"Indexed","scheduling":{"schedulingPolicy":{"gang":{}},"disruptionMode":{"all":{}}}}' \
  | kubectl apply -f -
kubectl get workload -n builder-demo -o yaml | sed -n '/^  spec:/,/^  status/p'
#   podGroupTemplates: - name: …-pgt-0   schedulingPolicy: gang: minCount: 3     <- defaulted from parallelism
kubectl get podgroup -n builder-demo -o jsonpath='{.items[0].spec}{"\n"}'          # disruptionMode all, workloadRef → the Workload
kubectl get pods -n builder-demo -o custom-columns=NAME:.metadata.name,GROUP:.spec.schedulingGroup.podGroupName
kubectl get workload,podgroup -n builder-demo -o jsonpath='{range .items[*]}{.kind}{" owner="}{.metadata.ownerReferences[0].kind}{"\n"}{end}'   # owned by the Job -> GC'd with it
```

## Lab 3 – Validation done by the library
```bash
kubectl create job bad -n builder-demo --image=busybox:1.36 --dry-run=client -o json -- true \
  | jq '.spec.scheduling={"schedulingPolicy":{"basic":{}},"disruptionMode":{"all":{}}}' | kubectl apply --dry-run=server -f -
#   the disruptionMode `all` is not supported with the Basic scheduling policy
```

---

## Cleanup
```bash
kubectl delete namespace builder-demo
```
