# Install Drivers and Allocate Devices with DRA – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/cluster-management/install-use-dra/

> Runs on the default **minikube** (v1.37; DRA `resource.k8s.io/v1` is on by default). All manifests are the docs examples **verbatim**
> (`examples/dra/driver-install/…` → this folder, `…/example/…` → [example/](example/)). The driver is the upstream
> `registry.k8s.io/dra-example-driver/dra-example-driver:v0.2.0`, which simulates **9 GPUs** per node.
>
> **Notes:**
> - Single node: one driver Pod, one ResourceSlice (`minikube-gpu.example.com-…`, pool `minikube`), not the page's two kind workers.
> - "Confirm your nodes have access to the image" uses `docker pull` on the node. minikube's runtime is containerd, so it's
>   `minikube ssh -- sudo crictl pull …` here.
> - The claim status also contains `allocationTimestamp`, which the page's sample doesn't show.
> - **The docs' cleanup leaves files on the node** (written through the driver's hostPath volumes):
>   `/var/lib/kubelet/plugins/gpu.example.com/checkpoint.json` and `/var/run/cdi/k8s.gpu.example.com-gpu_common.yaml`.
>   [cleanup.sh](cleanup.sh) removes them.

## Key ideas (read first)

| Object | Role |
|---|---|
| DRA driver (DaemonSet, kubelet plugin) | registers with the kubelet (`/var/lib/kubelet/plugins_registry`), publishes devices, prepares/unprepares them, writes CDI specs (`/var/run/cdi`) |
| ResourceSlice | the devices one driver offers on one node, with attributes and capacity (here 80Gi "memory" each) |
| DeviceClass `gpu.example.com` | a named filter (`device.driver == 'gpu.example.com'`) |
| ResourceClaim `some-gpu` | "one device of that class with memory ≥ 10Gi" (CEL); the scheduler allocates a device and the Pod is reserved on it |
| PriorityClass | keeps the driver from being preempted, since Pods with claims depend on it |

## Lab 1 – Initial state
```bash
kubectl get deviceclasses                 # No resources found
kubectl get resourceslices                # No resources found
kubectl get resourceclaims -A             # No resources found
kubectl get resourceclaimtemplates -A     # No resources found
```

## Lab 2 – Install the driver
```bash
kubectl create namespace dra-tutorial
minikube ssh -- sudo crictl pull registry.k8s.io/dra-example-driver/dra-example-driver:v0.2.0      # (docs: docker pull …)
kubectl apply --server-side -f deviceclass.yaml           # deviceclass.resource.k8s.io/gpu.example.com serverside-applied
kubectl apply --server-side -f serviceaccount.yaml
kubectl apply --server-side -f clusterrole.yaml
kubectl apply --server-side -f clusterrolebinding.yaml
kubectl apply --server-side -f priorityclass.yaml
kubectl apply --server-side -f daemonset.yaml
kubectl get pod -l app.kubernetes.io/name=dra-example-driver -n dra-tutorial
#   dra-example-driver-kubeletplugin-sbmtd   1/1   Running
kubectl get resourceslices
#   minikube-gpu.example.com-sxcjq   minikube   gpu.example.com   minikube   2s
# NOT from the docs – what is advertised:
kubectl get resourceslices -o jsonpath='{range .items[0].spec.devices[*]}{.name} {.capacity.memory.value} {.attributes.model}{"\n"}{end}'
#   gpu-0 80Gi {"string":"LATEST-GPU-MODEL"}   … gpu-0 … gpu-8 (9 devices)
```

## Lab 3 – Claim a device
```bash
kubectl apply --server-side -f example/resourceclaim.yaml
kubectl apply --server-side -f example/pod.yaml
kubectl get pod pod0 -n dra-tutorial                     # 1/1 Running
kubectl logs pod0 -c ctr0 -n dra-tutorial | grep -E "GPU_DEVICE_[0-9]+=" | grep -v "RESOURCE_CLAIM"
#   declare -x GPU_DEVICE_0="gpu-0"
#   (all of them: GPU_DEVICE_0_RESOURCE_CLAIM="1bea10e6-…", _SHARING_STRATEGY="TimeSlicing", _TIMESLICE_INTERVAL="Default")
kubectl get resourceclaims -n dra-tutorial               # some-gpu   allocated,reserved
kubectl get resourceclaim some-gpu -n dra-tutorial -o yaml
#   status.allocation: allocationTimestamp, devices.results: device gpu-0 / driver gpu.example.com / pool minikube / request some-gpu,
#                      nodeSelector metadata.name In [minikube]
#   status.reservedFor: pod0
kubectl logs -l app.kubernetes.io/name=dra-example-driver -n dra-tutorial
#   driver.go:107] PrepareResourceClaims is called: number of claims: 1
#   driver.go:134] Returning newly prepared devices for claim '1bea10e6-…': [{[some-gpu] minikube gpu-0 [k8s.gpu.example.com/gpu=common k8s.gpu.example.com/gpu=1bea10e6-…-gpu-0]}]
```

## Lab 4 – Delete the Pod
```bash
kubectl delete pod pod0 -n dra-tutorial
kubectl get resourceclaims -n dra-tutorial               # some-gpu   pending      (status: {} – deallocated)
kubectl logs -l app.kubernetes.io/name=dra-example-driver -n dra-tutorial | grep Unprepare
#   driver.go:139] UnprepareResourceClaims is called: number of claims: 1
minikube ssh -- ls /var/run/cdi                          # only k8s.gpu.example.com-gpu_common.yaml (per-claim spec gone)
```
NOT from the docs – a claim no device can satisfy (memory ≥ 100Gi, every mock GPU has 80Gi):
```bash
#   pod-huge   0/1   Pending
#   0/1 nodes are available: 1 cannot allocate all claims. preemption: … Preemption is not helpful for scheduling.
```

## Cleanup
```bash
./cleanup.sh
#   docs: delete namespace dra-tutorial, deviceclass gpu.example.com, clusterrole dra-example-driver-role,
#         clusterrolebinding dra-example-driver-role-binding, priorityclass dra-driver-high-priority
#   + the two leftover files on the node
```
