# Device Plugins – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/

> The docs' Pod is **verbatim** in [demo-pod.yaml](demo-pod.yaml). It asks for 2 × `hardware-vendor.example/foo`. To give it real devices, this lab runs a **toy device plugin** that speaks the kubelet's gRPC API, built from the kubelet's own `api.proto` files:
>
> | File | What |
> |---|---|
> | [toy-plugin/plugin.py](toy-plugin/plugin.py) | ~130 lines of Python. 4 fake devices `foo-0..3` (NUMA 0). Implements `GetDevicePluginOptions`, `ListAndWatch`, `GetPreferredAllocation` (prefers the **highest** IDs, so you can see it), `Allocate` (env + device nodes + mounts + annotation) and `PreStartContainer`. Re-registers when a kubelet restart deletes its socket. |
> | [toy-plugin/podresources.py](toy-plugin/podresources.py) | PodResources API client (`List`, `GetAllocatableResources`, `Get`), i.e. what a monitoring agent does |
> | [toy-plugin/deviceplugin.proto](toy-plugin/deviceplugin.proto), [podresources.proto](toy-plugin/podresources.proto) | Copied unchanged from kubernetes v1.37.0 (`k8s.io/kubelet/pkg/apis/...`) |
> | [toy-plugin/Dockerfile](toy-plugin/Dockerfile) | python:3.12-slim + grpcio, generates the stubs |
> | [00-plugin.yaml](00-plugin.yaml) | Namespace `dp-demo`, the plugin as a **privileged DaemonSet** with `/var/lib/kubelet/device-plugins` mounted, and a `monitor` Pod with `/var/lib/kubelet/pod-resources` mounted |
> | [01-consumer.yaml](01-consumer.yaml) | Requests 1 device and prints what the plugin injected |

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Device plugin** | A vendor daemon (usually a DaemonSet) that advertises hardware (GPUs, NICs, FPGAs…) to the **kubelet** over gRPC, with no changes to Kubernetes code. Stable since v1.26. |
| **Registration** | The plugin first **serves** its `DevicePlugin` service on a socket in `/var/lib/kubelet/device-plugins/` (a hard-coded path). It **then** calls `Register` on `kubelet.sock` with its socket name, API version (`v1beta1`) and resource name (`vendor-domain/type`). |
| **Advertising** | The plugin streams devices and their health over `ListAndWatch`. The kubelet puts the count into node `capacity`/`allocatable`. |
| **Requesting** | Container `limits: {vendor/res: N}`. Integers only, no overcommit (request = limit), and a device is **never shared** between containers. |
| **Allocate** | Called at container creation. The plugin returns what to add to the container: **env vars, device nodes, mounts, annotations, CDI device names**. `GetPreferredAllocation` and `PreStartContainer` are optional; `GetDevicePluginOptions` says which ones exist. |
| **kubelet restart** | Deletes every socket in the directory, so plugins must notice and re-register. |
| **Unhealthy devices** | `allocatable` drops, `capacity` stays. Pods already holding the device keep it. `allocatedResourcesStatus` in the container status (feature `ResourceHealthStatus`, beta, on by default since v1.36) shows per-device health. |
| **PodResources API** | kubelet gRPC on `/var/lib/kubelet/pod-resources/kubelet.sock`: `List` (all Pods' devices, exclusive CPUs, memory, DRA claims), `GetAllocatableResources`, `Get` (one Pod, beta). Mount the **directory** so the socket survives kubelet restarts. |
| **Topology Manager** | Devices report `TopologyInfo` (NUMA nodes) so the kubelet can align them with CPUs (see `../../../resource-management/resource-managers`). |
| **vs. DRA** | Device plugins = count-based, node-local. DRA (`../../../resource-management/dynamic-resource-allocation`) = claims, attributes, sharing. |

---

## Step 1 – Build and deploy the plugin
```bash
cd concepts/extend-kubernetes/compute-storage-net/device-plugins
minikube image build -t toy-foo-plugin:1 toy-plugin/          # straight into the node's containerd
kubectl apply -f 00-plugin.yaml
kubectl logs ds/toy-foo-plugin -n dp-demo
#   08:49:23 serving on /var/lib/kubelet/device-plugins/toy-foo.sock     <- serve first
#   08:49:23 GetDevicePluginOptions                                       <- the kubelet calls back right away
#   08:49:23 registered hardware-vendor.example/foo with the kubelet      <- then register
#   08:49:23 ListAndWatch -> foo-0=Healthy, foo-1=Healthy, foo-2=Healthy, foo-3=Healthy
kubectl get node minikube -o jsonpath='{.status.capacity.hardware-vendor\.example/foo} {.status.allocatable.hardware-vendor\.example/foo}'
#   4 4
```

## Lab 1 – The docs' Pod, and what Allocate injects
```bash
kubectl apply -f demo-pod.yaml -n dp-demo                    # 2 devices
kubectl apply -f 01-consumer.yaml                            # 1 device
kubectl logs ds/toy-foo-plugin -n dp-demo | tail -6
#   GetPreferredAllocation available=['foo-3', 'foo-0', 'foo-1', 'foo-2'] size=2 -> ['foo-3', 'foo-2']
#   Allocate ['foo-2', 'foo-3']                                  <- the kubelet followed the preference
#   PreStartContainer ['foo-3', 'foo-2']  (e.g. reset the device)
#   GetPreferredAllocation available=['foo-0', 'foo-1'] size=1 -> ['foo-1']
#   Allocate ['foo-1']
#   PreStartContainer ['foo-1']
kubectl logs consumer -n dp-demo
#   FOO_DEVICES=foo-1                                            <- env
#   crw-rw-rw-  1 root root 1, 3 ... /dev/foo-1                  <- device node (the node's /dev/null, char 1,3)
#   toy foo device foo-1                                         <- mount /etc/foo/foo-1 from the node
CID=$(kubectl get pod consumer -n dp-demo -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's|.*://||')
minikube ssh -- "sudo crictl inspect $CID | grep -m1 foo-devices"
#   "hardware-vendor.example/foo-devices": "foo-1"               <- annotation: goes to the runtime, not the Pod object
kubectl describe node minikube | grep -A12 "Allocated resources" | grep foo
#   hardware-vendor.example/foo  3  3
```

## Lab 2 – Extended-resource rules
```bash
kubectl run greedy -n dp-demo --image=busybox:1.36 --overrides='{"spec":{"containers":[{"name":"greedy","image":"busybox:1.36","command":["sleep","3600"],"resources":{"limits":{"hardware-vendor.example/foo":"2"}}}]}}'
#   Pending: 0/1 nodes are available: 1 Insufficient hardware-vendor.example/foo.      (1 free, needs 2)
```
Server dry-runs:

| resources | Result |
|---|---|
| `limits: 500m` | `"500m": must be an integer` |
| `requests: 1, limits: 2` | `must be equal to hardware-vendor.example/foo limit of 2` (no overcommit) |
| `requests: 1` only | `Limit must be set for non overcommitable resources` |
| `limits: 1` only | accepted (requests defaulted to the limit) |

## Lab 3 – Unhealthy devices
```bash
P=$(kubectl get pod -n dp-demo -l app=toy-foo-plugin -o name)
kubectl exec -n dp-demo $P -- sh -c 'printf "foo-0\nfoo-1\n" > /run/toy/unhealthy'    # foo-1 is in use by "consumer"
#   plugin: ListAndWatch -> foo-0=Unhealthy, foo-1=Unhealthy, foo-2=Healthy, foo-3=Healthy
kubectl get node minikube -o jsonpath='{.status.capacity.hardware-vendor\.example/foo} {.status.allocatable.hardware-vendor\.example/foo}'
#   4 2                                     <- capacity unchanged, allocatable reduced (after the next node status update)
kubectl get pod consumer -n dp-demo -o jsonpath='{.status.phase} {.status.containerStatuses[0].allocatedResourcesStatus}'
#   Running [{"name":"hardware-vendor.example/foo","resources":[{"health":"Unhealthy","resourceID":"foo-1"}]}]
kubectl exec -n dp-demo $P -- sh -c ': > /run/toy/unhealthy'                            # heal
```
The Pod keeps running on its unhealthy device. Kubernetes only reports it, and the app has to fail or cope.

## Lab 4 – kubelet restart
```bash
minikube ssh -- 'sudo systemctl restart kubelet'
kubectl logs ds/toy-foo-plugin -n dp-demo --tail=5
#   08:51:27 socket deleted (kubelet restarted?) -> re-serving and re-registering
#   08:51:28 serving on /var/lib/kubelet/device-plugins/toy-foo.sock
#   08:51:28 registered hardware-vendor.example/foo with the kubelet
#   08:51:28 ListAndWatch -> foo-0=Healthy, ...                 allocatable back to 4; running Pods untouched
```

## Lab 5 – PodResources API (a monitoring agent's view)
```bash
kubectl delete pod consumer -n dp-demo                       # frees foo-1, greedy now gets ['foo-1','foo-0']
kubectl exec monitor -n dp-demo -- python podresources.py allocatable
#   hardware-vendor.example/foo ['foo-1'] numa=[0]   ... one entry per device, 4 in total
#   cpus []                                          <- no exclusive CPUs (CPU manager policy none)
kubectl exec monitor -n dp-demo -- python podresources.py list
#   dp-demo/greedy/greedy: hardware-vendor.example/foo ['foo-0'] numa=[0]
#   dp-demo/greedy/greedy: hardware-vendor.example/foo ['foo-1'] numa=[0]
#   dp-demo/demo-pod/demo-container-1: hardware-vendor.example/foo ['foo-3'] numa=[0]
#   dp-demo/demo-pod/demo-container-1: hardware-vendor.example/foo ['foo-2'] numa=[0]
kubectl exec monitor -n dp-demo -- python podresources.py get greedy dp-demo
```
Device ID to pod/namespace/container is exactly what a GPU exporter needs to label its metrics.

## Lab 6 – The plugin goes away
```bash
kubectl delete ds toy-foo-plugin -n dp-demo
#   once the plugin Pod is gone (~30s, Python ignores SIGTERM):  capacity=4 allocatable=0
```
New Pods can't get devices any more. Pods already running keep theirs (`greedy` and `demo-pod` stay Running). The stale capacity is dropped later: within ~400s (the kubelet's endpoint grace period) it went to `capacity=0`. The resource name stays listed with 0 rather than disappearing.

---

## Useful commands
```bash
kubectl get node <n> -o jsonpath='{.status.allocatable}'
kubectl describe node <n> | grep -A12 "Allocated resources"
kubectl get pod <p> -o jsonpath='{.status.containerStatuses[*].allocatedResourcesStatus}'
```

## Cleanup
```bash
./cleanup.sh        # namespace, /var/lib/toy-foo on the node, the image
```
