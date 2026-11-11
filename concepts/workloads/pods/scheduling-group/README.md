# Scheduling Group – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/scheduling-group/

> Cluster: the `wl-lab` profile (`../../workload-api/start-wl-lab.sh`), because `GenericWorkload` is off by default.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **`spec.schedulingGroup.podGroupName`** | Links a Pod to a [PodGroup](../../podgroup-api/) in the **same namespace**, so the scheduler places the group together. |
| **Immutable** | Once set, the Pod can't move to another group. |
| **basic group** | Pods are scheduled one by one, and the group acts as a label. |
| **gang group** | All-or-nothing for `minCount` Pods. None bind until enough can. |
| **CompositePodGroup parent** | (`CompositePodGroup`, alpha) The scheduler applies the policies of the whole tree. |
| **Missing references** | A missing PodGroup, or a missing parent CompositePodGroup, means the Pod stays **Pending** until the hierarchy exists, then it's reconsidered automatically. |

## The demo app
[worker-0.yaml](worker-0.yaml) is the docs Pod **verbatim** (`some-ns`, group `training-worker-0`, placeholder image `training:v1`).

---

## Lab 1 – The docs Pod before its PodGroup exists
```bash
cd concepts/workloads/pods/scheduling-group
kubectl create namespace some-ns
kubectl apply -f worker-0.yaml
kubectl get pod worker-0 -n some-ns                # Pending, no events - waiting for PodGroup training-worker-0
kubectl apply -f - <<'YAML'
apiVersion: scheduling.k8s.io/v1beta1
kind: PodGroup
metadata: {name: training-worker-0, namespace: some-ns}
spec: {schedulingPolicy: {basic: {}}}
YAML
kubectl get pod worker-0 -n some-ns                # now scheduled -> ErrImagePull (training:v1 is a placeholder image)
kubectl get pod worker-0 -n some-ns -o jsonpath='{.spec.nodeName} {.spec.schedulingGroup}{"\n"}'
```

## Lab 2 – Immutable membership
```bash
kubectl patch pod worker-0 -n some-ns -p '{"spec":{"schedulingGroup":{"podGroupName":"other"}}}'
#   Forbidden: pod updates may not change fields ...
```
Gang behaviour (members wait for each other): [../../workload-api/policies](../../workload-api/policies/). Composite parents: [../../compositepodgroup-api](../../compositepodgroup-api/).

---

## Cleanup
```bash
kubectl delete namespace some-ns
```
