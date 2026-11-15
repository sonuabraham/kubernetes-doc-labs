# Resize CPU and Memory Resources assigned to Pods – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/resize-pod-resources/

> Runs on the default **minikube** cluster (v1.37). All four required gates are already on:
> `InPlacePodLevelResourcesVerticalScaling` and `PodLevelResources` are beta and on by default, `InPlacePodVerticalScaling` is GA, and so is
> `NodeDeclaredFeatures`. File: [pod-level-resize.yaml](pod-level-resize.yaml) (docs, **verbatim**, default namespace).
> Read [../resize-container-resources](../resize-container-resources/) first. Conditions, `Deferred` and the
> QoS rules are identical for pod-level resize.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **What is resized** | `spec.resources`: the Pod-wide envelope (pod cgroup) set by [pod-level resources](../assign-pod-level-resources/). Same `--subresource resize`. |
| **No pod-level `resizePolicy`** | Changing `spec.resources` itself never restarts anything… |
| **…but containers may restart** | A container with **no limit of its own** inherits the pod limit in its cgroup. If the pod limit changes, that container's effective limit changes too, so its own `resizePolicy` (`RestartContainer`) applies. |
| **Validation** | Pod requests ≥ **sum** of container requests. Each container limit ≤ pod limit (the *sum* of container limits may exceed it). QoS class still can't change. |
| **Status order** | `status.containerStatuses` is sorted **by container name**, not spec order. Here `[0]` is `nginx-server` and `[1]` is `pause`, so the page's "`containerStatuses[1]` restarted" actually refers to `nginx-server`. Select by name. |

## The demo Pod
```
Pod pod-level-resize-demo   spec.resources  req=lim  cpu 200m  memory 200Mi  -> Guaranteed
 ├─ pause         requests cpu 100m mem 100Mi, no limits     resizePolicy cpu: NotRequired   mem: RestartContainer
 └─ nginx-server  nothing set                                 resizePolicy cpu: RestartContainer mem: RestartContainer
    (both containers inherit the pod limits: cpu.max 20000 100000, memory.max 200Mi)
```

---

## Step 0
```bash
cd tasks/configure-pod-container/resize-pod-resources
kubectl create -f pod-level-resize.yaml
kubectl wait --for=condition=Ready pod/pod-level-resize-demo
S(){ kubectl get pod pod-level-resize-demo -o json | jq -c '{gen:.metadata.generation, obs:.status.observedGeneration,
  pod:.spec.resources.limits, restarts:([.status.containerStatuses[]|{(.name):.restartCount}]|add), qos:.status.qosClass,
  conds:[.status.conditions[]|select(.type|startswith("PodResize"))|{type,reason,message}]}'; }
S
#   {"gen":1,"obs":1,"pod":{"cpu":"200m","memory":"200Mi"},"restarts":{"nginx-server":0,"pause":0},"qos":"Guaranteed","conds":[]}
```
`registry.k8s.io/nginx:latest` takes a few seconds to pull.

The cgroups on the node (pod slice, sandbox, then the two containers):
```bash
C(){ U=$(kubectl get po pod-level-resize-demo -o jsonpath='{.metadata.uid}' | tr - _)
     minikube ssh -- "cd /sys/fs/cgroup/kubepods.slice/kubepods-pod$U.slice; echo pod \$(cat cpu.max) \$(cat memory.max);
       for c in cri-containerd-*.scope; do echo \${c:15:12} \$(cat \$c/cpu.max) \$(cat \$c/memory.max); done"; }
C
#   pod           20000 100000 209715200
#   30421f572f51  max 100000 max              <- sandbox (pause of the pod infra)
#   b9824d45db47  20000 100000 209715200      <- pause container: inherits the pod limit
#   d0fb7751c1aa  20000 100000 209715200      <- nginx-server: inherits the pod limit
```

## Lab 1 – Resize pod-level CPU (the docs' example)
```bash
kubectl patch pod pod-level-resize-demo --subresource resize --patch \
  '{"spec":{"resources":{"requests":{"cpu":"300m"}, "limits":{"cpu":"300m"}}}}'
S
#   {"gen":2,"obs":2,"pod":{"cpu":"300m","memory":"200Mi"},"restarts":{"nginx-server":1,"pause":0},…}
C
#   pod           30000 100000 209715200
#   b9824d45db47  30000 100000 209715200      <- same container ID: updated live (cpu NotRequired)
#   c3a2eac8cd91  30000 100000 209715200      <- NEW container ID: nginx-server was restarted (cpu RestartContainer)
```

## Lab 2 – Resize pod-level memory (not from the docs)
```bash
kubectl patch pod pod-level-resize-demo --subresource resize --patch \
  '{"spec":{"resources":{"requests":{"memory":"250Mi"}, "limits":{"memory":"250Mi"}}}}'
S
#   {"gen":3,"pod":{"cpu":"300m","memory":"250Mi"},"restarts":{"nginx-server":2,"pause":1},…}
```
Both containers restarted: both have `memory: RestartContainer` and no memory limit of their own.

## Lab 3 – Validation rules (not from the docs)
```bash
kubectl patch pod pod-level-resize-demo --subresource resize --patch \
  '{"spec":{"resources":{"requests":{"cpu":"50m"}, "limits":{"cpu":"50m"}}}}'
#   … spec.resources.requests[cpu]: Invalid value: "50m": must be greater than or equal to aggregate container requests of 100m

kubectl patch pod pod-level-resize-demo --subresource resize --patch \
  '{"spec":{"containers":[{"name":"pause","resources":{"requests":{"cpu":"100m"},"limits":{"cpu":"400m"}}}]}}'
#   … spec.resources.containers[0][cpu].limits: Invalid value: "400m": must be less than or equal to pod limits of 300m

kubectl patch pod pod-level-resize-demo --subresource resize --patch \
  '{"spec":{"resources":{"requests":{"cpu":"250m"}, "limits":{"cpu":"300m"}}}}'
#   … spec: Invalid value: "Guaranteed": Pod QOS Class may not change as a result of resizing

kubectl patch pod pod-level-resize-demo --subresource resize --patch \
  '{"spec":{"containers":[{"name":"pause","resources":{"requests":{"cpu":"100m"},"limits":{"cpu":"250m"}}}]}}'
#   pod/pod-level-resize-demo patched   <- a container limit (≤ pod limit) can be ADDED; pause: cpu NotRequired, no restart
S
#   {"gen":4,…,"restarts":{"nginx-server":2,"pause":1}}
```

## Useful commands
```bash
kubectl patch pod <p> --subresource resize --patch '{"spec":{"resources":{"limits":{"cpu":"…"}}}}'
kubectl get pod <p> -o jsonpath='{.spec.resources}'
kubectl get pod <p> -o jsonpath='{range .status.containerStatuses[*]}{.name}={.restartCount} {end}'
```

## Cleanup
```bash
./cleanup.sh      # kubectl delete pod pod-level-resize-demo
```
