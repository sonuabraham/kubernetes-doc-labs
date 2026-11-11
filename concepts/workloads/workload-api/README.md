# Workload API – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/workload-api/

> Sub-pages: [policies](policies/), [disruption-and-priority](disruption-and-priority/), [topology-aware-scheduling](topology-aware-scheduling/), [workloadbuilder](workloadbuilder/). Related: [../podgroup-api](../podgroup-api/), [../compositepodgroup-api](../compositepodgroup-api/), [../pods/scheduling-group](../pods/scheduling-group/).
> ⚠️ **Off by default in v1.37** (`GenericWorkload` beta = false, `scheduling.k8s.io/v1beta1` not served). Use the lab profile: **`./start-wl-lab.sh`** (minikube profile `wl-lab`, one node with 8 allocatable CPUs).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Workload** | `scheduling.k8s.io/v1beta1`. A **static, long-lived policy template** describing how groups of Pods must be scheduled. No runtime state. **Immutable** spec. |
| **podGroupTemplates** | Up to 8 named templates, each with a scheduling policy (`basic` / `gang`) plus optional `priorityClassName` and `disruptionMode`. |
| **PodGroup** | The **runtime** instance created from a template (by a controller, or by you). It holds a copy of the policy and the status. |
| **Pods** | Join a group with `spec.schedulingGroup.podGroupName`. |
| **controllerRef** | Points back to the owning Job/CRD, for tooling only. |
| **compositePodGroupTemplates** | (`CompositePodGroup`, alpha, `v1alpha3`) Hierarchical groups: multi-level gang (`minGroupCount`) and topology. A union with `podGroupTemplates` (one or the other). Max depth 4, max 8 per list. |
| **Jobs** | (`WorkloadWithJob`, alpha) `.spec.scheduling` on a Job makes the Job controller create the Workload and PodGroup for you. `gang: {}` → `minCount = parallelism`. Without `scheduling` the Job uses `basic` (classic pod-by-pod). |
| **Note** | The `WorkloadAwarePreemption` gate from v1.36 was merged into `GenericWorkload` in v1.37. |

## The demo app
The docs examples are **verbatim**: [workload-training-job.yaml](workload-training-job.yaml) (`training-job-workload` in `some-ns`) and [workload-gang-of-gangs.yaml](workload-gang-of-gangs.yaml) (`v1alpha3`, 2 × minCount 4). [00-prereqs.yaml](00-prereqs.yaml) creates namespace `some-ns` and PriorityClass `high-priority` they reference.
[01-gang-vs-basic.yaml](01-gang-vs-basic.yaml), [02-gang-fits.yaml](02-gang-fits.yaml) and [03-gang-topology.yaml](03-gang-topology.yaml) are gang scheduling through Jobs, sized for one 8-CPU node.

---

## Step 0 – A cluster with the API turned on
```bash
cd concepts/workloads/workload-api
./start-wl-lab.sh
#   compositepodgroups  scheduling.k8s.io/v1alpha3  CompositePodGroup
#   podgroups           scheduling.k8s.io/v1beta1   PodGroup
#   workloads           scheduling.k8s.io/v1beta1   Workload
```

## Lab 1 – The docs' Workloads
```bash
kubectl apply -f 00-prereqs.yaml -f workload-training-job.yaml -f workload-gang-of-gangs.yaml
kubectl get workloads -A
kubectl get workload training-job-workload -n some-ns -o yaml | sed -n '/^spec:/,$p'
kubectl patch workload training-job-workload -n some-ns --type=json -p '[{"op":"replace","path":"/spec/podGroupTemplates/0/schedulingPolicy/gang/minCount","value":3}]'
#   patched - minCount is the one mutable field; adding or removing templates is rejected
```
A Workload alone schedules nothing. It's a template. Labs 2–4 create PodGroups from templates through a Job.

## Lab 2 – Gang vs basic through Jobs
```bash
kubectl apply -f 01-gang-vs-basic.yaml ; sleep 15
kubectl get pods -n gang-demo -L job-name --no-headers | awk '{print $NF, $3}' | sort | uniq -c
#   2 basic-too-big Running        <- basic: whatever fits gets bound (8 × 2.5 CPU on an 8-CPU node)
#   6 basic-too-big Pending
#   8 gang-too-big  Pending        <- gang: all-or-nothing -> none bound, no capacity wasted
kubectl get workloads,podgroups -n gang-demo        # the Job controller created one Workload + PodGroup per Job
kubectl get events -n gang-demo --field-selector reason=FailedScheduling -o custom-columns=M:.message | grep -m1 minCount
#   pod group is unschedulable ... minCount (8) cannot be satisfied: 3 scheduled, 4 remaining ...
kubectl get pod -n gang-demo -l job-name=gang-too-big -o jsonpath='{.items[0].spec.schedulingGroup}{"\n"}'
#   {"podGroupName":"gang-too-big-…-pgt-0-…"}           <- set by the Job controller
```

## Lab 3 – A gang that fits starts together
```bash
kubectl delete job basic-too-big gang-too-big -n gang-demo
kubectl apply -f 02-gang-fits.yaml ; sleep 12
kubectl get pods -n gang-demo -l job-name=gang-fits -o custom-columns=PHASE:.status.phase,START:.status.startTime --no-headers | sort | uniq -c
#   8 Running 2026-11-11T21:41:32Z        <- all 8 bound in the same scheduling cycle
```

## Lab 4 – The docs' gang Job (and an API mismatch)
```bash
kubectl create namespace training
kubectl apply -f ../controllers/job/job-gang-distributed-training.yaml
#   Error ... strict decoding error: unknown field "spec.scheduling.schedulingConstraints.key"
kubectl apply -f ../controllers/job/job-gang-distributed-training-v1.37.yaml      # topology: [{key: ...}] instead
kubectl get workloads,podgroups -n training     # PodGroup Gang ... Unschedulable  (each pod wants an nvidia.com/gpu)
```
Topology-constrained gangs: see [topology-aware-scheduling](topology-aware-scheduling/) (Lab 2 uses `03-gang-topology.yaml`).

---

## Useful commands
```bash
kubectl get workloads,podgroups,compositepodgroups -A
kubectl explain workload.spec --recursive ; kubectl explain job.spec.scheduling --recursive
kubectl get pods -o custom-columns=NAME:.metadata.name,GROUP:.spec.schedulingGroup.podGroupName,PHASE:.status.phase
```

## Cleanup
```bash
./cleanup.sh
minikube stop -p wl-lab ; kubectl config use-context minikube
```
