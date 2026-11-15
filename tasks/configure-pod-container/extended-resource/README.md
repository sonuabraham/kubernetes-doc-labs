# Assign Extended Resources to a Container – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/extended-resource/

> Runs on the default **minikube** cluster. Lab 1 repeats the advertise step from
> [Advertise Extended Resources for a Node](../../administer-cluster/extended-resource-node/). Lab 4 uses the lab's own DRA
> driver from [../assign-resources](../assign-resources/) (`driver.sh`, run on the `minikube` node with `P=minikube`).
> Files: [extended-resource-pod.yaml](extended-resource-pod.yaml), [extended-resource-pod-2.yaml](extended-resource-pod-2.yaml)
> (docs, **verbatim**). Not from the docs: [dra-deviceclass.yaml](dra-deviceclass.yaml), [dra-extended-resource-pod.yaml](dra-extended-resource-pod.yaml).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Extended resource** | A fully-qualified name outside `kubernetes.io` (`example.com/dongle`) with an **integer** count. The scheduler only does bookkeeping; it doesn't know what a dongle is. |
| **Requests = limits** | Extended resources can't be overcommitted. You need a limit. A limit alone defaults the request to it, and request ≠ limit is rejected. |
| **Two providers** | (a) the Node advertises capacity (by hand or via a **device plugin**), or (b) **DRA**: a DeviceClass with `extendedResourceName` (gate `DRAExtendedResource`, GA in 1.37). The Pod spec is the same in both cases. |
| **DRA under the hood** | The scheduler creates a ResourceClaim `<pod>-extended-resources-<x>` and records it in `pod.status.extendedResourceClaimStatus`. The driver then prepares real devices. |

```
         Pod: resources.limits example.com/dongle: 3            Pod: resources.limits example.com/gpu: 2
                       │                                                   │
 scheduler: node.status.allocatable["example.com/dongle"]=4   DeviceClass gpu.example.com (extendedResourceName)
            minus what other Pods use                          → ResourceClaim → devices from ResourceSlices
```

---

## Step 0 – Advertise four dongles on the node
```bash
cd tasks/configure-pod-container/extended-resource
kubectl proxy --port=8001 & PROXY=$!; sleep 2
curl --header "Content-Type: application/json-patch+json" --request PATCH \
  --data '[{"op": "add", "path": "/status/capacity/example.com~1dongle", "value": "4"}]' \
  http://localhost:8001/api/v1/nodes/minikube/status | jq -c .status.capacity
kill $PROXY
sleep 12; kubectl get node minikube -o jsonpath='{.status.allocatable.example\.com/dongle}{"\n"}'
#   4                 <- the kubelet copied capacity to allocatable
```

## Lab 1 – A Pod that uses 3 dongles (docs)
```bash
kubectl apply -f extended-resource-pod.yaml
kubectl get pod extended-resource-demo                  # Running
kubectl describe pod extended-resource-demo | grep -A1 -E '^\s+(Limits|Requests):'
#   Limits:    example.com/dongle:  3
#   Requests:  example.com/dongle:  3
```

## Lab 2 – A second Pod wants 2 more (docs)
```bash
kubectl apply -f extended-resource-pod-2.yaml
kubectl get pod extended-resource-demo-2
#   extended-resource-demo-2   0/1   Pending
kubectl describe pod extended-resource-demo-2 | grep -E 'PodScheduled|FailedScheduling'
#   PodScheduled   False
#   Warning  FailedScheduling … 0/1 nodes are available: 1 Insufficient example.com/dongle. preemption: … No preemption victims found
kubectl describe node minikube | grep dongle
#   example.com/dongle:  4      (capacity)
#   example.com/dongle:  4      (allocatable)
#   example.com/dongle  3  3    (allocated requests / limits)
kubectl delete pod extended-resource-demo --now
kubectl get pod extended-resource-demo-2                # Running a few seconds later: 2 of 4 now fit
```

## Lab 3 – Validation rules (not from the docs)
```bash
t(){ printf '%-14s ' "$1"; kubectl run er-test --image=nginx --dry-run=server -o name \
  --overrides="{\"spec\":{\"containers\":[{\"name\":\"er-test\",\"image\":\"nginx\",\"resources\":$2}]}}" 2>&1 | cut -c1-150; }
t "request only"  '{"requests":{"example.com/dongle":"1"}}'
t "limit only"    '{"limits":{"example.com/dongle":"1"}}'
t "request<limit" '{"requests":{"example.com/dongle":"1"},"limits":{"example.com/dongle":"2"}}'
t "fractional"    '{"requests":{"example.com/dongle":"500m"},"limits":{"example.com/dongle":"500m"}}'
t "no domain"     '{"limits":{"dongle":"1"}}'
```
| Case | Result |
|---|---|
| request only | `resources.limits: Required value: Limit must be set for non overcommitable resources` |
| limit only | accepted. The stored Pod has `requests: {example.com/dongle: "1"}` filled in. |
| request < limit | `requests: Invalid value: "1": must be equal to example.com/dongle limit of 2` |
| `500m` | `must be an integer` |
| `dongle` (no domain) | `must be a standard resource type or fully qualified` |
| `requests.example.com/dongle` | `doesn't follow extended resource name standard` (the `requests.` prefix is reserved for quota) |
| `kubernetes.io/dongle`, `foo.kubernetes.io/dongle` | **accepted** in a Pod. The page's "not `*.kubernetes.io/`" rule is about the names you *advertise*; the Pod API treats these as native names. |

## Lab 4 – The same request, served by DRA (the page's last section)
```bash
P=minikube ../assign-resources/driver.sh start driver.example.com 3
#   active
#   driver.example.com-reg.sock
kubectl get resourceslices -o json | jq -c '.items[]|{driver:.spec.driver, devices:[.spec.devices[].name]}'
#   {"driver":"driver.example.com","devices":["gpu-0","gpu-1","gpu-2"]}
kubectl apply -f dra-deviceclass.yaml -f dra-extended-resource-pod.yaml
kubectl logs dra-extended-resource-demo
#   GPU_DEVICE_0=gpu-0
#   GPU_DEVICE_0_CLAIM=default/dra-extended-resource-demo-extended-resources-54hlv
#   GPU_DEVICE_1=gpu-1
#   …
kubectl get pod dra-extended-resource-demo -o json | jq -c .status.extendedResourceClaimStatus
#   {"requestMappings":[{"containerName":"ctr","requestName":"container-0-request-0","resourceName":"example.com/gpu"}],
#    "resourceClaimName":"dra-extended-resource-demo-extended-resources-54hlv"}
kubectl get resourceclaims
#   dra-extended-resource-demo-extended-resources-54hlv   allocated,reserved
kubectl get node minikube -o json | jq -c '.status.allocatable | with_entries(select(.key|startswith("example.com")))'
#   {"example.com/dongle":"4"}         <- the node never advertises example.com/gpu
```
A second copy of the Pod (2 more GPUs, only 1 left) stays Pending. The message is DRA's, not "Insufficient":
```bash
sed 's/name: dra-extended-resource-demo$/name: dra-extended-resource-demo-2/' dra-extended-resource-pod.yaml | kubectl apply -f -
kubectl describe pod dra-extended-resource-demo-2 | grep FailedScheduling
#   0/1 nodes are available: 1 cannot allocate all claims. …
```

## Useful commands
```bash
kubectl describe node minikube | grep -A12 'Allocated resources'
kubectl get pods -o custom-columns=NAME:.metadata.name,DONGLES:.spec.containers[*].resources.limits.example\\.com/dongle
kubectl get resourceclaims,resourceslices,deviceclasses
```

## Cleanup
```bash
./cleanup.sh     # Pods, DeviceClass, lab driver + its ResourceSlice, and the node's dongle capacity
```
