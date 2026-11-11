# PodGroup API – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/podgroup-api/

> Sub-page: [lifecycle](lifecycle/). Cluster: the `wl-lab` profile (`../workload-api/start-wl-lab.sh`), with `GenericWorkload` and `scheduling.k8s.io/v1beta1` on.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **PodGroup** | `scheduling.k8s.io/v1beta1`. The **runtime** object for a group of Pods that's scheduled as a unit. It holds the scheduling policy, optional topology constraints, priority, disruption mode, DRA claims, and status. |
| **From a template** | Controllers create PodGroups from a Workload's `podGroupTemplates`. `spec.workloadRef` (`workloadName`, `templateName`) records that. You can also create them yourself. |
| **Pods** | `spec.schedulingGroup.podGroupName` (same namespace). |
| **schedulingPolicy** | **Required**: `basic` or `gang: {minCount}`. |
| **resourceClaims** | DRA devices **shared by the group** (`DRAWorkloadResourceClaims`). |
| **Status** | `PodGroupInitiallyScheduled`-type conditions; the STATUS column shows `Pending`, `Scheduled` or `Unschedulable`. |
| **parentCompositePodGroupName** | Makes it a leaf under a [CompositePodGroup](../compositepodgroup-api/). |

## The demo app
The docs examples are **verbatim**: [podgroup-training-worker-0.yaml](podgroup-training-worker-0.yaml) (a stand-alone gang of 4), [workload-podgroup-pod.yaml](workload-podgroup-pod.yaml) (Workload `training-policy` + PodGroup + Pod `worker-0`), and the snippets `spec-*-snippet.yaml` / [resourceclaims-excerpt.yaml](resourceclaims-excerpt.yaml).
[workload-podgroup-pod-v1.37.yaml](workload-podgroup-pod-v1.37.yaml) is the same trio adjusted to the served API.

---

## Lab 1 – A stand-alone PodGroup
```bash
cd concepts/workloads/podgroup-api
kubectl apply -f podgroup-training-worker-0.yaml
kubectl get podgroup training-worker-0           # Gang  <none>  Pending   (no pods yet)
kubectl delete podgroup training-worker-0
```

## Lab 2 – Workload → PodGroup → Pod (the docs' "How it fits together")
```bash
kubectl apply -f workload-podgroup-pod.yaml
#   workload.scheduling.k8s.io/training-policy created
#   pod/worker-0 created
#   Error ... PodGroup in version "v1beta1" cannot be handled as a PodGroup: strict decoding error: unknown field "spec.podGroupTemplateRef"
kubectl explain podgroup.spec.workloadRef         # the served field: workloadName + templateName
kubectl apply -f workload-podgroup-pod-v1.37.yaml
kubectl get workload training-policy ; kubectl get podgroup training-worker-0 -o jsonpath='{.spec.workloadRef}{"\n"}'
kubectl get pod worker-0                          # Pending - gang of 4 has 1 member (and "training:v1" is a placeholder image)
```
The docs page and the topology page disagree (`podGroupTemplateRef.workload.podGroupTemplateName` vs `workloadRef.templateName`), and v1.37 serves `workloadRef`.

## Lab 3 – Gang behaviour with a user-managed PodGroup
See [../workload-api/policies](../workload-api/policies/): 3 members wait, and the 4th makes all four start together.

---

## Useful commands
```bash
kubectl get podgroups -A
kubectl get podgroup <pg> -o jsonpath='{.status.conditions}'
kubectl get pods -o custom-columns=NAME:.metadata.name,GROUP:.spec.schedulingGroup.podGroupName
```

## Cleanup
```bash
kubectl delete -f workload-podgroup-pod-v1.37.yaml --ignore-not-found
```
