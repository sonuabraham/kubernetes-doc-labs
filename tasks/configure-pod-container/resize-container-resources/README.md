# Resize CPU and Memory Resources assigned to Containers – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/resize-container-resources/

> Labs 1–5 run on the default **minikube** cluster (v1.37, `InPlacePodVerticalScaling` GA).
> Labs 6–7 need two **alpha** gates, so they use a throwaway profile started by [start-resize-lab.sh](start-resize-lab.sh).
> **Stop the default `minikube` first.** With two clusters running, this host runs out of inotify instances
> (`kube-proxy: fsnotify watcher init: too many open files`).
>
> Files: [pod-resize.yaml](pod-resize.yaml) (docs, **verbatim**). Not from the docs:
> [never-restart-policy.yaml](never-restart-policy.yaml), [sidecar-resize.yaml](sidecar-resize.yaml),
> [emptydir-memory-resize.yaml](emptydir-memory-resize.yaml), [preemption-demo.yaml](preemption-demo.yaml).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Desired vs actual** | `spec.containers[*].resources` is what you *want*. `status.containerStatuses[*].resources` is what the kubelet *applied* to the running container. `allocatedResources` is what the kubelet has reserved. |
| **`/resize` subresource** | The only way to change CPU/memory of a running Pod: `kubectl patch/edit/apply --subresource resize` (kubectl ≥ 1.32). A normal Pod update still rejects resource changes. |
| **`resizePolicy`** | Per resource: `NotRequired` (default, apply live) or `RestartContainer`. If any resource changed needs a restart, the container restarts. |
| **Conditions** | `PodResizePending` (`Infeasible` / `Deferred`, kubelet can't grant it now) and `PodResizeInProgress` (accepted, being applied; `reason: Error` if actuation fails). |
| **Deferred retry order** | Higher PriorityClass first, then Guaranteed before Burstable, then the longest-waiting. With gate `InPlacePodVerticalScalingSchedulerPreemption` (alpha), the scheduler **preempts** lower-priority Pods to make room. |
| **Limits** | CPU/memory only. **QoS class can't change.** Limits/requests can't be removed. No Windows. No static CPU/Memory-manager Pods. `restartPolicy: Never` ⇒ all `NotRequired`. |
| **1.37 vs the page** | ① A resize larger than the node's **allocatable** is now **refused by the API server** (`Forbidden`), so it never becomes `Infeasible`. ② Regular init containers *can* be resized: `InPlacePodVerticalScalingInitContainers` is GA. |

---

## Step 0
```bash
cd tasks/configure-pod-container/resize-container-resources
kubectl get --raw /metrics | grep -E 'kubernetes_feature_enabled\{name="InPlacePodVerticalScaling'
#   InPlacePodVerticalScaling                        ""     1   (GA)
#   InPlacePodVerticalScalingInitContainers          ""     1   (GA)
#   InPlacePodVerticalScalingMemoryBackedVolumes     ALPHA  0
#   InPlacePodVerticalScalingSchedulerPreemption     ALPHA  0
kubectl create namespace qos-example
# a helper to see everything that matters in one line
S(){ kubectl get pod ${1:-resize-demo} -n qos-example -o json | jq -c '{gen:.metadata.generation, obsGen:.status.observedGeneration,
  spec:.spec.containers[0].resources.requests, actual:.status.containerStatuses[0].resources.requests,
  restarts:.status.containerStatuses[0].restartCount, qos:.status.qosClass,
  conds:[.status.conditions[]|select(.type|startswith("PodResize"))|{type,reason,message}]}'; }
```

## Lab 1 – Resize CPU without restart (docs Example 1)
```bash
kubectl create -f pod-resize.yaml -n qos-example
kubectl wait --for=condition=Ready pod/resize-demo -n qos-example; S
#   {"gen":1,"obsGen":1,"spec":{"cpu":"700m","memory":"200Mi"},"actual":{"cpu":"700m","memory":"200Mi"},"restarts":0,"qos":"Guaranteed","conds":[]}
kubectl patch pod resize-demo -n qos-example --subresource resize --patch \
  '{"spec":{"containers":[{"name":"pause", "resources":{"requests":{"cpu":"800m"}, "limits":{"cpu":"800m"}}}]}}'
S
#   {"gen":2,"obsGen":2,"spec":{"cpu":"800m",…},"actual":{"cpu":"800m",…},"restarts":0,…}   <- live, no restart
```
`metadata.generation` goes up with each resize. `status.observedGeneration` shows the kubelet has processed it.

## Lab 2 – Resize memory with restart (docs Example 2)
```bash
kubectl patch pod resize-demo -n qos-example --subresource resize --patch \
  '{"spec":{"containers":[{"name":"pause", "resources":{"requests":{"memory":"300Mi"}, "limits":{"memory":"300Mi"}}}]}}'
sleep 5; S
#   {"gen":3,"obsGen":3,"spec":{"cpu":"800m","memory":"300Mi"},"actual":{"cpu":"800m","memory":"300Mi"},"restarts":1,…}
```
`restartCount` 0 → 1 because memory has `restartPolicy: RestartContainer`.

The node's cgroups now hold the new values:
```bash
U=$(kubectl -n qos-example get po resize-demo -o jsonpath='{.metadata.uid}' | tr - _)
minikube ssh -- "cd /sys/fs/cgroup/kubepods.slice/kubepods-pod$U.slice; cat cpu.max memory.max"
#   80000 100000      <- 800m
#   314572800         <- 300Mi
```

## Lab 3 – An impossible resize (docs "Infeasible")
```bash
kubectl patch pod resize-demo -n qos-example --subresource resize --patch \
  '{"spec":{"containers":[{"name":"pause", "resources":{"requests":{"cpu":"1000"}, "limits":{"cpu":"1000"}}}]}}'
#   Error from server (Forbidden): pods "resize-demo" is forbidden: node didn't have enough allocatable resources:
#   cpu, requested: 1000000, allocatable: 8000
S    # unchanged: gen 3, cpu 800m - nothing was stored
```
**Different from the page.** In 1.37 the API server checks the request against the node's allocatable and
refuses it, so the Pod never gets a `PodResizePending / Infeasible` condition.

## Lab 4 – A resize that has to wait: `Deferred` (not from the docs)
Ask for something that fits the node, but not next to the Pods already there:
```bash
kubectl patch pod resize-demo -n qos-example --subresource resize --patch \
  '{"spec":{"containers":[{"name":"pause", "resources":{"requests":{"cpu":"7500m"}, "limits":{"cpu":"7500m"}}}]}}'
S
#   {"gen":4,"obsGen":4,"spec":{"cpu":"7500m",…},"actual":{"cpu":"800m",…},
#    "conds":[{"type":"PodResizePending","reason":"Deferred","message":"Node didn't have enough resource: cpu, requested: 7500, used: 950, capacity: 8000"}]}
kubectl patch pod resize-demo -n qos-example --subresource resize --patch \
  '{"spec":{"containers":[{"name":"pause", "resources":{"requests":{"cpu":"800m"}, "limits":{"cpu":"800m"}}}]}}'
S    # condition gone, gen 5
```

## Lab 5 – The rules (not from the docs)
```bash
# QoS class may not change (Guaranteed -> Burstable)
kubectl patch pod resize-demo -n qos-example --subresource resize --patch \
  '{"spec":{"containers":[{"name":"pause", "resources":{"requests":{"cpu":"500m"}}}]}}'
#   The Pod "resize-demo" is invalid: spec: Invalid value: "Guaranteed": Pod QOS Class may not change as a result of resizing

# without --subresource resize, resources are still immutable
kubectl patch pod resize-demo -n qos-example --patch \
  '{"spec":{"containers":[{"name":"pause", "resources":{"requests":{"cpu":"900m"}, "limits":{"cpu":"900m"}}}]}}'
#   The Pod "resize-demo" is invalid: spec: Forbidden: pod updates may not change fields other than `spec.containers[*].image`, …

# restartPolicy: Never forbids RestartContainer
kubectl apply -f never-restart-policy.yaml
#   … spec.containers[0].resizePolicy: Invalid value: "RestartContainer": must be 'NotRequired' when pod `restartPolicy` is 'Never'

# sidecars and (in 1.37) regular init containers can be resized; limits can't be removed
kubectl apply -f sidecar-resize.yaml; kubectl wait --for=condition=Ready pod/sidecar-demo -n qos-example
kubectl patch pod sidecar-demo -n qos-example --subresource resize --patch '{"spec":{"initContainers":[{"name":"sidecar","resources":{"requests":{"cpu":"150m"}}}]}}'
#   pod/sidecar-demo patched
kubectl patch pod sidecar-demo -n qos-example --subresource resize --patch '{"spec":{"initContainers":[{"name":"setup","resources":{"requests":{"cpu":"150m"}}}]}}'
#   pod/sidecar-demo patched     <- the page says non-restartable init containers can't; gate InPlacePodVerticalScalingInitContainers is GA
kubectl patch pod sidecar-demo -n qos-example --subresource resize --type=json -p '[{"op":"remove","path":"/spec/containers/0/resources/limits"}]'
#   … spec.containers[0].resources.limits: Forbidden: resource limits cannot be removed
```

## Lab 6 – Resize a memory-backed emptyDir (alpha gate, profile `resize-lab`)
```bash
minikube stop                      # free inotify instances for the second cluster
./start-resize-lab.sh              # switches kubectl to the resize-lab context
kubectl create namespace qos-example
kubectl apply -f emptydir-memory-resize.yaml
kubectl exec -n qos-example cache-demo -- df -h /cache
#   tmpfs   100.0M   0   100.0M   0% /cache
kubectl patch pod cache-demo -n qos-example --subresource resize --patch \
  '{"spec":{"volumes":[{"name":"cache-volume", "emptyDir":{"sizeLimit":"200Mi"}}]}}'   # the docs' command
kubectl exec -n qos-example cache-demo -- df -h /cache
#   tmpfs   200.0M   0   200.0M   0% /cache       <- tmpfs remounted live, restartCount still 0
```
Edge cases measured:
| Patch | Result |
|---|---|
| `sizeLimit: 500Mi` (more than the container's 300Mi memory limit) | accepted, `df` shows 500M. The memory cgroup still caps real usage at 300Mi. |
| shrink to 100Mi with 150MB already written | `PodResizeInProgress`, `reason: Error`, `failed to resize volume cache-volume: mount failed: exit status 32 … remount,size=104857600`. The volume stays 200M. |
| same patch on the default cluster (gate off) | `pod/cache-demo patched`, **but nothing changes**: generation stays 1, `sizeLimit` stays 100Mi, `df` shows 100M. With the gate off, `/resize` only takes container resources and silently drops the volume part. |

## Lab 7 – Deferred resize + scheduler preemption (alpha gate, profile `resize-lab`)
```bash
kubectl delete pod cache-demo -n qos-example --now
kubectl apply -f preemption-demo.yaml          # low-prio (800m, priority 10) + high-prio (200m, priority 1000)
kubectl patch pod high-prio -n qos-example --subresource resize --patch \
  '{"spec":{"containers":[{"name":"pause","resources":{"requests":{"cpu":"6500m"}}}]}}'
kubectl get events -n qos-example --sort-by=.lastTimestamp | tail -5
```
```
Warning ResizeDeferred  pod/high-prio  Pod resize OutOfcpu: … "error":"Node didn't have enough resource: cpu, requested: 6500, used: 1650, capacity: 8000"
Normal  Preempted       pod/low-prio   Preempted by pod d7cf8fff-… on node resize-lab
Normal  Killing         pod/low-prio   Stopping container pause
Normal  ResizeStarted   pod/high-prio  Pod resize started: …"generation":3
Normal  ResizeCompleted pod/high-prio  Pod resize completed: …
```
The whole sequence took about one second. Note the docker driver shows the host's 8 CPUs as allocatable,
even though the profile was started with `--cpus 2`.
```bash
minikube delete -p resize-lab; minikube start; kubectl config use-context minikube
```

## Useful commands
```bash
kubectl patch pod <p> --subresource resize --patch '{"spec":{"containers":[{"name":"<c>","resources":{…}}]}}'
kubectl edit pod <p> --subresource resize
kubectl get pod <p> -o jsonpath='{.status.containerStatuses[0].resources}'
kubectl get pod <p> -o jsonpath='{.status.conditions[?(@.type=="PodResizePending")]}'
kubectl get events --field-selector reason=ResizeDeferred
```

## Cleanup
```bash
./cleanup.sh
```
