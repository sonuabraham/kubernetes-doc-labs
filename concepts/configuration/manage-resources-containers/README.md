# Resource Management for Pods and Containers – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

> Docs manifests are **verbatim**: [01-frontend.yaml](01-frontend.yaml), [02-extended-resource-pod.yaml](02-extended-resource-pod.yaml) (`my-pod`) and [pod-level-resources.yaml](pod-level-resources.yaml) (pinned to namespace `pod-resources-example`). The docs' images (`images.my-company.example/…`, `myimage`) are placeholders, so runnable twins use busybox. Requires `minikube addons enable metrics-server` for `kubectl top`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **request** | What the **scheduler** reserves. A Pod fits a node only if the sum of requests ≤ allocatable. It also sets the CPU weight (share under contention). |
| **limit** | What the **kernel enforces** via cgroups. CPU above the limit is **throttled**; memory above the limit is **OOM-killed** (container restarts per restartPolicy). |
| **Limit only** | No request + a limit → request = limit (unless an admission default applies). |
| **Units** | CPU: `1` = 1 vCPU/core, `250m` = 0.25, min precision `1m`. Memory: bytes, `Mi`/`Gi` (2^n) or `M`/`G` (10^n). **`400m` memory = 0.4 bytes!** |
| **Pod-level resources** (`PodLevelResources`, beta, on) | `spec.resources` for the whole Pod: a shared budget containers can borrow from. Only cpu, memory, hugepages. |
| **In-place resize** | `--subresource resize`, container-level (GA) and **pod-level** (`InPlacePodLevelResourcesVerticalScaling`, beta, on). |
| **Extended resources** | Node-advertised integers (`example.com/foo`) from device plugins or a status PATCH. Request **must equal** limit, integers only, no overcommit. Cluster-level ones belong to scheduler extenders. |
| **Ephemeral storage, hugepages, PIDs** | Also resources: see `../../storage/ephemeral-storage`. PID limits are per node/Pod via kubelet config. |
| **MemoryQoS** (beta, on) | Uses cgroup v2 `memory.high` for throttling before the hard limit. |

---

## Step 1
```bash
cd concepts/configuration/manage-resources-containers
kubectl apply -f 00-setup.yaml
kubectl apply -n res-demo -f 01-frontend.yaml -f 03-frontend-runnable.yaml -f 04-memory-hog.yaml -f 05-limit-only.yaml
kubectl apply -f pod-level-resources.yaml
```

## Lab 1 – Requests are for scheduling
```bash
kubectl get pod frontend -n res-demo -o wide        # ErrImagePull, but SCHEDULED: its 500m CPU/128Mi requests fit
kubectl run greedy -n res-demo --image=busybox:1.36 --overrides='{"spec":{"containers":[{"name":"greedy","image":"busybox:1.36","command":["sleep","3600"],"resources":{"requests":{"cpu":"100"}}}]}}'
kubectl get events -n res-demo --field-selector involvedObject.name=greedy,reason=FailedScheduling -o custom-columns=M:.message
#   0/1 nodes are available: 1 Insufficient cpu.
kubectl describe node minikube | sed -n '/Allocated resources/,/Events/p'
#   cpu     2750m (34%)  2900m (36%)        <- sum of requests / limits on the node
```

## Lab 2 – CPU limit = throttling
```bash
kubectl top pod frontend-runnable -n res-demo --containers
#   app              502m    <- a busy loop, capped at its 500m limit
#   log-aggregator   1m
kubectl exec frontend-runnable -c app -n res-demo -- sh -c 'cat /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max; grep throttled /sys/fs/cgroup/cpu.stat'
#   50000 100000        <- 50ms per 100ms period = 0.5 CPU
#   134217728           <- 128Mi
#   nr_throttled 606  throttled_usec 30219723
```

## Lab 3 – Memory limit = OOM kill
```bash
kubectl get pod memory-hog -n res-demo -o jsonpath='restarts={.status.containerStatuses[0].restartCount} last={.status.containerStatuses[0].lastState.terminated.reason}/{.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
#   restarts=3 last=OOMKilled/137           <- tried 200Mi with a 128Mi limit; CrashLoopBackOff follows
kubectl describe pod memory-hog -n res-demo | grep -A3 'Last State'     # the docs' "My container is terminated" troubleshooting
```

## Lab 4 – Limit without request, and units
```bash
kubectl get pod limit-only -n res-demo -o jsonpath='{.spec.containers[0].resources} qos={.status.qosClass}{"\n"}'
#   {"limits":{"cpu":"300m","memory":"64Mi"},"requests":{"cpu":"300m","memory":"64Mi"}} qos=Guaranteed
kubectl run tiny -n res-demo --image=busybox:1.36 --dry-run=server --overrides='{"spec":{"containers":[{"name":"tiny","image":"busybox:1.36","resources":{"requests":{"memory":"400m"}}}]}}'
#   Warning: spec.containers[0].resources.requests[memory]: fractional byte value "400m" is invalid, must be an integer
kubectl run tinycpu -n res-demo --image=busybox:1.36 --dry-run=server -o jsonpath='{.spec.containers[0].resources}' --overrides='{"spec":{"containers":[{"name":"tinycpu","image":"busybox:1.36","resources":{"requests":{"cpu":"0.0005"}}}]}}'
#   {"requests":{"cpu":"1m"}}       <- rounded up to the 1m precision
```
`400m` memory only gets a **warning**: the Pod is accepted with a 0.4-byte request.

## Lab 5 – Pod-level resources (docs `pod-resources-demo`)
```bash
U=$(kubectl get pod pod-resources-demo -n pod-resources-example -o jsonpath='{.metadata.uid}' | tr - _)
minikube ssh -- "d=/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod$U.slice; cat \$d/cpu.max \$d/memory.max; for c in \$d/cri-containerd-*.scope; do echo \$(cat \$c/cpu.max) \$(cat \$c/memory.max); done"
#   100000 100000 / 209715200            <- POD cgroup: 1 CPU, 200Mi (spec.resources.limits)
#   50000 100000 104857600               <- ctr-1: its own 0.5 CPU / 100Mi
#   max 100000 max                       <- ctr-2 (fedora): no container limits, bounded only by the pod's
```
Resize the **pod-level** budget in place:
```bash
kubectl patch pod pod-resources-demo -n pod-resources-example --subresource=resize \
  -p '{"spec":{"resources":{"limits":{"cpu":"2","memory":"300Mi"},"requests":{"cpu":"1","memory":"100Mi"}}}}'
kubectl get pod pod-resources-demo -n pod-resources-example -o jsonpath='{.status.resources} restarts={.status.containerStatuses[*].restartCount}{"\n"}'
#   {"limits":{"cpu":"2","memory":"300Mi"},"requests":{"cpu":"1","memory":"100Mi"}} restarts=0 0
```
Container-level in-place resize is shown in `../../workloads/autoscaling`, Lab 2.

## Lab 6 – Extended resources
The docs advertise `example.com/foo` with a raw `curl` PATCH of the node status (`~1` = `/`). kubectl does the same:
```bash
kubectl patch node minikube --subresource=status --type=json -p '[{"op":"add","path":"/status/capacity/example.com~1foo","value":"5"}]'
kubectl get node minikube -o jsonpath='{.status.allocatable.example\.com/foo}'      # 5   (allocatable follows a moment later)
kubectl apply -n res-demo -f 02-extended-resource-pod.yaml          # docs my-pod: scheduled (ImagePullBackOff - "myimage" is a placeholder)
kubectl apply -n res-demo -f 06-extended-resource-runnable.yaml     # 6 more Pods wanting 1 foo each
kubectl get pods -n res-demo -l app=foo-users                       # 4 Running, 2 Pending (my-pod holds the 5th)
#   0/1 nodes are available: 1 Insufficient example.com/foo.
kubectl run x -n res-demo --image=busybox:1.36 --dry-run=server --overrides='{"spec":{"containers":[{"name":"o","image":"busybox:1.36","resources":{"requests":{"example.com/foo":"1"},"limits":{"example.com/foo":"2"}}}]}}'
#   requests: Invalid value: "1": must be equal to example.com/foo limit of 2
#   (and "500m": must be an integer)
```
Nothing *enforces* "foo" at runtime: it's pure scheduler accounting. A device plugin also makes the device available in the container. The docs' cluster-level example is a legacy scheduler **Policy** JSON. Today that's `extenders[].managedResources` in a `KubeSchedulerConfiguration`.

---

## Useful commands
```bash
kubectl describe node <n> | sed -n '/Allocated resources/,/Events/p'
kubectl top pod --containers ; kubectl top node
kubectl get pod <p> -o jsonpath='{.status.qosClass}'
kubectl patch pod <p> --subresource resize -p '{"spec":{...}}'
```

## Cleanup
```bash
./cleanup.sh       # namespaces + removes example.com/foo from the node
```
