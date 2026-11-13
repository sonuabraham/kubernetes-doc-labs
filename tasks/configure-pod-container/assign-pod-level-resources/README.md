# Assign Pod-level CPU and memory resources – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/assign-pod-level-resources/

> Runs on the default **minikube** cluster (v1.37, metrics-server enabled). Files:
> - [pod-level-memory-request-limit.yaml](pod-level-memory-request-limit.yaml), [pod-level-cpu-request-limit.yaml](pod-level-cpu-request-limit.yaml), [pod-level-resources.yaml](pod-level-resources.yaml): the docs' examples, **verbatim**.
> - [pod-level-memory-request-limit-fixed.yaml](pod-level-memory-request-limit-fixed.yaml) (**not from the docs**): the docs' memory Pod runs `stress` in the `nginx` image, which has no such binary. The fix swaps in `polinux/stress`.
> - [unsupported-resource.yaml](unsupported-resource.yaml), [pod-smaller-than-containers.yaml](pod-smaller-than-containers.yaml) (**not from the docs**): validation rules.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`spec.resources`** | Requests and limits for the **whole Pod**, alongside (or instead of) per-container `resources`. Gate `PodLevelResources`: beta, **on by default** in 1.37 (the docs' "must be enabled" is already true). |
| **Precedence** | If set, pod-level requests are what the scheduler counts, and pod-level values decide the **QoS class**. |
| **Sharing** | Containers without their own values share the pod's budget. The pod cgroup enforces the pod limit, so all containers *together* stay under it. Containers with their own limits are also capped individually. |
| **Rules** | Only `cpu`, `memory` and `hugepages-*`. Pod requests must be ≥ the sum of container requests, and container limits must be ≤ the pod limits. Not for Windows. |
| **Related gates** | `PodLevelResourceManagers` (CPU/Memory/Topology manager alignment): beta, **off** here. `InPlacePodLevelResourcesVerticalScaling`: the page says alpha, but the 1.37 server reports it **beta and enabled**. |

---

## Step 0
```bash
cd tasks/configure-pod-container/assign-pod-level-resources
kubectl get --raw /metrics | grep -E 'kubernetes_feature_enabled\{name="(PodLevelResources|PodLevelResourceManagers|InPlacePodLevelResourcesVerticalScaling)"'
#   InPlacePodLevelResourcesVerticalScaling  BETA 1
#   PodLevelResourceManagers                 BETA 0
#   PodLevelResources                        BETA 1
kubectl create namespace pod-resources-example
```

## Lab 1 – Memory request and limit at pod level
```bash
kubectl apply -f pod-level-memory-request-limit.yaml --namespace=pod-resources-example
kubectl get pod memory-demo --namespace=pod-resources-example
#   memory-demo   0/1   CrashLoopBackOff
#   ... exec: "stress": executable file not found in $PATH          <- docs bug: nginx image
kubectl delete pod memory-demo -n pod-resources-example --now
kubectl apply -f pod-level-memory-request-limit-fixed.yaml --namespace=pod-resources-example
kubectl get pod memory-demo --output=json --namespace=pod-resources-example | jq -c '.spec.resources, .spec.containers[0].resources, .status.qosClass'
#   {"limits":{"memory":"200Mi"},"requests":{"memory":"100Mi"}}     <- pod level
#   {}                                                            <- the container sets nothing
#   "Burstable"
kubectl top pod memory-demo --namespace=pod-resources-example
#   memory-demo   69m   150Mi       <- above the 100Mi request, within the 200Mi limit
```

## Lab 2 – CPU request and limit at pod level
```bash
kubectl apply -f pod-level-cpu-request-limit.yaml --namespace=pod-resources-example
kubectl get pod cpu-demo --namespace=pod-resources-example -o jsonpath='{.spec.resources}'
#   {"limits":{"cpu":"1"},"requests":{"cpu":"500m"}}
kubectl top pod cpu-demo --namespace=pod-resources-example
#   cpu-demo   1001m   1Mi          <- tries 2 CPUs, throttled to the pod's 1 CPU
```

## Lab 3 – Pod level and container level together
```bash
kubectl apply -f pod-level-resources.yaml --namespace=pod-resources-example
kubectl get pod pod-resources-demo --output=json --namespace=pod-resources-example | jq -c '.spec.containers[] | [.name, .resources]'
#   ["pod-resources-demo-ctr-1",{"limits":{"cpu":"500m","memory":"100Mi"},"requests":{"cpu":"500m","memory":"50Mi"}}]
#   ["pod-resources-demo-ctr-2",{}]
kubectl get pod pod-resources-demo -n pod-resources-example -o jsonpath='{.spec.resources}'
#   {"limits":{"cpu":"1","memory":"200Mi"},"requests":{"cpu":"1","memory":"100Mi"}}
```

## Lab 4 – What the node really enforces (not from the docs)
cgroup v2 values for each Pod, read on the node:
```bash
U=$(kubectl -n pod-resources-example get po pod-resources-demo -o jsonpath='{.metadata.uid}' | tr - _)
minikube ssh -- "d=/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod$U.slice; cat \$d/memory.max \$d/cpu.max; for c in \$d/cri-containerd-*.scope; do echo \$(cat \$c/memory.max) \$(cat \$c/cpu.max); done"
```
| cgroup | memory.max | cpu.max | |
|---|---|---|---|
| pod slice | 209715200 (200Mi) | 100000 100000 (1 CPU) | the pod limit, shared by all containers |
| ctr-1 | 104857600 (100Mi) | 50000 100000 (0.5 CPU) | its own, tighter limit |
| ctr-2 | 209715200 | 100000 100000 | no own limit: **inherits the pod limit** |
| pause (sandbox) | max | max | |

The same holds for `memory-demo` (pod 200Mi, container 200Mi) and `cpu-demo` (pod and container `cpu.max 100000 100000`). Inside ctr-2, `cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max` prints `209715200` / `100000 100000`.

The scheduler counts the pod-level requests. **kubectl version matters here**: an older client computes them from containers only.
```bash
kubectl describe node minikube | grep pod-resources-example                   # kubectl v1.35 client:
#   pod-resources-demo   500m (6%)  500m (6%)  50Mi (0%)  100Mi (0%)              <- container sums: WRONG
#   cpu-demo / memory-demo   0 0 0 0
minikube ssh -- 'sudo /var/lib/minikube/binaries/v1.37.0/kubectl --kubeconfig /etc/kubernetes/admin.conf describe node minikube' | grep pod-resources-example
#   cpu-demo             500m (6%)  1 (12%)    0 (0%)      0 (0%)
#   memory-demo          0 (0%)     0 (0%)     100Mi (0%)  200Mi (0%)
#   pod-resources-demo   1 (12%)    1 (12%)    100Mi (0%)  200Mi (0%)               <- pod level: right
```

## Lab 5 – Limitations (not from the docs)
```bash
kubectl apply --dry-run=server -f unsupported-resource.yaml
#   spec.resources.limits[ephemeral-storage]: Unsupported value: "ephemeral-storage": supported values: "cpu", "hugepages-", "memory"
kubectl apply --dry-run=server -f pod-smaller-than-containers.yaml
#   spec.resources.requests[cpu]: Invalid value: "500m": must be greater than or equal to aggregate container requests of 800m
```

---

## Useful commands
```bash
kubectl get pod <p> -o jsonpath='{.spec.resources}{"\n"}{.status.qosClass}'
kubectl top pod <p> --containers
```

## Clean up (the docs' command)
```bash
kubectl delete namespace pod-resources-example
```
