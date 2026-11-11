# Pods – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/

> Sub-pages: [pod-lifecycle](pod-lifecycle/), [pod-condition](pod-condition/), [init-containers](init-containers/), [sidecar-containers](sidecar-containers/), [ephemeral-containers](ephemeral-containers/), [probes](probes/), [disruptions](disruptions/), [pod-hostname](pod-hostname/), [pod-qos](pod-qos/), [scheduling-group](scheduling-group/), [static-pods](static-pods/), [user-namespaces](user-namespaces/), [downward-api](downward-api/), [advanced-pod-config](advanced-pod-config/).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Pod** | The smallest deployable unit: one or more containers with **shared network and storage** and a spec for running them. A "logical host". Usually one container per Pod; several only when they're tightly coupled. |
| **Shared context** | Linux namespaces + cgroups: **one IP and port space** (containers talk over `localhost`), **one IPC namespace** (`/dev/shm`, SysV IPC), shared **volumes**, hostname = Pod name. Each container still has its own image filesystem. |
| **Ephemeral** | A Pod stays on its node until it finishes, is deleted, is evicted, or the node fails. Restarting a container ≠ restarting a Pod. Create Pods through workload resources, not by hand. |
| **Pod template** | The `template` inside Deployments/Jobs/StatefulSets. Changing it creates **new** Pods. Existing ones aren't patched. |
| **In-place updates** | Only `containers[*].image`, `initContainers[*].image`, `activeDeadlineSeconds` (set, or lower only), `terminationGracePeriodSeconds`, `tolerations` (add only), `schedulingGates`. Name, namespace and uid are immutable. |
| **Subresources** | `resize` (CPU/memory in place), `ephemeralContainers`, `status` (the kubelet), `binding` (the scheduler). |
| **Generation** | `metadata.generation` goes up on spec changes. The kubelet reports `status.observedGeneration`. |
| **`spec.os.name`** | `linux`/`windows`. The **kubelet** rejects a mismatch, but the **scheduler ignores it**, so add a `kubernetes.io/os` nodeSelector too. |
| **Security** | `securityContext`: at minimum Baseline and non-root. |
| **Requests / limits** | Requests guide **scheduling**. Limits are **enforced** (CPU throttling, memory OOM kill). |

## The demo app
The docs examples are **verbatim**: [simple-pod.yaml](simple-pod.yaml) (`nginx:1.14.2`), [job-hello.yaml](job-hello.yaml) (the "pod template" Job) and [security-context-demo.yaml](security-context-demo.yaml). Extra: [01-shared-context.yaml](01-shared-context.yaml), [02-windows-pod.yaml](02-windows-pod.yaml), [03-resizable.yaml](03-resizable.yaml).

---

## Step 1
```bash
cd concepts/workloads/pods
kubectl apply -f 00-namespace.yaml
kubectl apply -f simple-pod.yaml -f job-hello.yaml -f security-context-demo.yaml -n pods-demo
kubectl get pods -n pods-demo
```

## Lab 1 – The docs examples
```bash
kubectl logs job/hello -n pods-demo                        # Hello, Kubernetes!   (a Pod made from the Job's pod template)
kubectl get pod -n pods-demo -l job-name=hello -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}{"\n"}'   # Job
kubectl exec security-context-demo -n pods-demo -- id      # uid=1000 gid=3000 groups=2000,3000  (runAsUser/runAsGroup/fsGroup)
```

## Lab 2 – What you can (and can't) update in place
```bash
kubectl patch pod nginx -n pods-demo -p '{"spec":{"containers":[{"name":"nginx","image":"nginx:1.27"}]}}'
kubectl get pod nginx -n pods-demo -o jsonpath='restarts={.status.containerStatuses[0].restartCount} gen={.metadata.generation} observed={.status.observedGeneration}{"\n"}'
#   restarts=1 gen=2 observed=2         <- image change = container restart, same Pod
kubectl patch pod nginx -n pods-demo -p '{"spec":{"containers":[{"name":"nginx","ports":[{"containerPort":8080}]}]}}'
#   Forbidden: pod updates may not change fields other than `spec.containers[*].image`, ...
kubectl patch pod nginx -n pods-demo -p '{"metadata":{"name":"renamed"}}'
#   the name of the object (renamed) does not match the name on the URL (nginx)
kubectl patch pod nginx -n pods-demo -p '{"spec":{"activeDeadlineSeconds":600}}'      # ok (set)
kubectl patch pod nginx -n pods-demo -p '{"spec":{"activeDeadlineSeconds":900}}'
#   Invalid value: 900: must be less than or equal to previous value                   <- only lower it
kubectl patch pod nginx -n pods-demo --type=json -p '[{"op":"add","path":"/spec/tolerations/-","value":{"key":"x","operator":"Exists"}}]'   # ok (add)
kubectl get pod nginx -n pods-demo -o jsonpath='gen={.metadata.generation} observed={.status.observedGeneration}{"\n"}'
```
`observedGeneration` can trail `generation` by one. That's the docs' "indirect status updates", reflecting the previous sync.

## Lab 3 – The shared context
```bash
kubectl apply -f 01-shared-context.yaml ; kubectl wait --for=condition=Ready pod/shared -n pods-demo
kubectl exec shared -c web    -n pods-demo -- sh -c 'curl -s localhost | head -1; cat /dev/shm/note; hostname'
#   <h1>written by writer at 12:49:45</h1>   <- file written by the OTHER container through the shared emptyDir
#   shm-from-writer                          <- shared IPC namespace (/dev/shm)
#   shared                                   <- hostname = Pod name
kubectl exec shared -c writer -n pods-demo -- sh -c 'wget -qO- localhost:80 | head -1; ps'
#   ...                                      <- writer reaches nginx on localhost: one network namespace
#   PID 1 = writer's own shell               <- processes are NOT shared (see shareProcessNamespace in advanced-pod-config)
kubectl get pod shared -n pods-demo -o jsonpath='{.status.podIP}{"\n"}'     # ONE IP for both containers
```

## Lab 4 – Pod templates create new Pods
```bash
kubectl create deployment tpl -n pods-demo --image=nginx:1.27 --replicas=2
kubectl get pods -n pods-demo -l app=tpl -o name
kubectl set env deployment/tpl -n pods-demo COLOR=blue          # change the TEMPLATE
kubectl rollout status deployment/tpl -n pods-demo
kubectl get pods -n pods-demo -l app=tpl -o name                # different names - replaced, not patched
```

## Lab 5 – spec.os.name
```bash
kubectl apply -f 02-windows-pod.yaml ; sleep 5
kubectl get pod wants-windows -n pods-demo -o jsonpath='{.spec.nodeName} {.status.phase} {.status.reason}: {.status.message}{"\n"}'
#   minikube Failed PodOSNotSupported: Pod was rejected: Failed to admit pod as the OS field doesn't match node OS
```
The **scheduler** put it on the Linux node anyway (`nodeName: minikube`). Only the **kubelet** checks `os.name`.

## Lab 6 – The resize subresource (in-place CPU change)
```bash
kubectl apply -f 03-resizable.yaml ; kubectl wait --for=condition=Ready pod/resizable -n pods-demo
kubectl exec resizable -n pods-demo -- cat /sys/fs/cgroup/cpu.max                   # 20000 100000  (200m)
kubectl patch pod resizable -n pods-demo --subresource resize \
  -p '{"spec":{"containers":[{"name":"c","resources":{"requests":{"cpu":"150m"},"limits":{"cpu":"300m"}}}]}}'
kubectl get pod resizable -n pods-demo -o jsonpath='spec={.spec.containers[0].resources.limits.cpu} actual={.status.containerStatuses[0].resources.limits.cpu} restarts={.status.containerStatuses[0].restartCount}{"\n"}'
#   spec=300m actual=300m restarts=0
kubectl exec resizable -n pods-demo -- cat /sys/fs/cgroup/cpu.max                   # 30000 100000  - changed live, no restart
```
A normal `kubectl patch` of `resources` is rejected (Lab 2's rule). The `resize` subresource is the only way.

---

## Useful commands
```bash
kubectl explain pod.spec --recursive | less
kubectl get pod <p> -o jsonpath='{.metadata.generation} {.status.observedGeneration}'
kubectl patch pod <p> --subresource resize -p '...'
kubectl exec <p> -c <container> -- <cmd>
```

## Cleanup
```bash
./cleanup.sh
```
