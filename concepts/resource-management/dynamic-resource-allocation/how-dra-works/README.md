# How DRA Works – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/how-dra-works/

> The docs' 5 blocks are **verbatim**: [prescheduled-pod-excerpt.yaml](prescheduled-pod-excerpt.yaml), [scheduler-binding-timeout.yaml](scheduler-binding-timeout.yaml), [binding-conditions-slice.yaml](binding-conditions-slice.yaml) and two node-allocatable slices. Uses the fake `gpu.example.com` driver (`../fake-dra.sh up`). For the docs' `dra.example.com` slice, **you play the driver** by patching claim status.

## Key ideas (read first)

| Step | Who | What |
|---|---|---|
| 1 | Admin / driver | DeviceClasses. The driver's node plugin publishes **ResourceSlices**. |
| 2 | User | Pod references a ResourceClaim or ResourceClaimTemplate. |
| 3 | Control plane | ResourceClaim controller creates claims from templates. **Scheduler** picks a node where all claims can be allocated, writes `status.allocation` and adds the Pod to `status.reservedFor`. |
| 4 | kubelet + driver | `NodePrepareResources` (CDI specs etc.), then containers start. On Pod removal: unprepare, unreserve, deallocate. |
| **Pre-scheduled Pods** | `spec.nodeName` set by the user skips the scheduler, so nobody allocates the claim and the kubelet refuses to run it. Use a `nodeSelector` on `kubernetes.io/hostname` instead (docs excerpt). |
| **Binding conditions** (beta) | Devices that need preparation *before* binding (e.g. attach over the fabric): the scheduler waits in **PreBind** until the device's `bindingConditions` are True in the claim status (failure conditions or `bindingTimeout` abort and retry). |
| **Node allocatable resources** (alpha) | Devices that consume or represent node CPU/memory (`nodeAllocatableResources`: mapping / overhead). |

---

## Step 1
```bash
cd concepts/resource-management/dynamic-resource-allocation/how-dra-works
../fake-dra.sh up
kubectl apply -f 00-setup.yaml        # namespace dra-how, class dra.example.com, claims slow-gpu, lifecycle
```

## Lab 1 – Claim lifecycle
```bash
st(){ kubectl get resourceclaim $1 -n dra-how -o jsonpath='allocated={.status.allocation.devices.results[0].pool}/{.status.allocation.devices.results[0].device} reservedFor=[{.status.reservedFor[*].name}]{"\n"}'; }
st lifecycle                                          # allocated=/ reservedFor=[]           <- a claim alone allocates nothing
# Pod user-1 referencing it:
st lifecycle                                          # allocated=fake-2/gpu-0 reservedFor=[user-1]
# Pod deleted:
st lifecycle                                          # allocated=/ reservedFor=[]           <- deallocated when the last consumer is gone
```

## Lab 2 – Pre-scheduled Pod
```bash
# the same claim, Pod with spec.nodeName: fake-1
st lifecycle                                          # allocated=/ reservedFor=[]           <- never allocated
kubectl get pod pinned -n dra-how -o wide             # Pending   fake-1   (a real kubelet would reject it: unallocated claim)
```

## Lab 3 – Device binding conditions (docs slice)
```bash
kubectl label node fake-2 accelerator-type=high-performance          # the slice's nodeSelector
kubectl apply -f binding-conditions-slice.yaml
# Pod waits-for-device using claim slow-gpu:
kubectl get pod waits-for-device -n dra-how -o jsonpath='node=[{.spec.nodeName}] nominated=[{.status.nominatedNodeName}]'
#   node=[] nominated=[fake-2]                         <- chosen, but NOT bound yet
kubectl get resourceclaim slow-gpu -n dra-how -o jsonpath='{.status.allocation.devices.results[0]}'
#   {"bindingConditions":["dra.example.com/is-prepared"],"bindingFailureConditions":["dra.example.com/preparing-failed"],"device":"gpu-1",...}
kubectl get events -n dra-how --field-selector involvedObject.name=waits-for-device -o custom-columns=R:.reason,M:.message
#   BindingConditionsPending   waiting for binding conditions for device on node fake-2
# now act as the driver: report the device prepared
kubectl patch resourceclaim slow-gpu -n dra-how --subresource=status --type=merge -p '{"status":{"devices":[{"driver":"dra.example.com","pool":"gpu-pool","device":"gpu-1","conditions":[{"type":"dra.example.com/is-prepared","status":"True","reason":"Ready","message":"attached","lastTransitionTime":"2026-11-12T00:00:00Z"}]}]}}'
kubectl get pod waits-for-device -n dra-how -o jsonpath='{.spec.nodeName}'         # fake-2   <- bound seconds later
```
[scheduler-binding-timeout.yaml](scheduler-binding-timeout.yaml) shortens how long the scheduler waits (`bindingTimeout`).

## Lab 4 – Node allocatable resources (alpha, off)
```bash
kubectl apply -f node-allocatable-cpu-mapping-slice.yaml --dry-run=server
#   cannot unmarshal string into Go struct field Device.spec.devices.capacity of type v1.DeviceCapacity
#   -> docs bug: capacity values must be objects:  "cpu.example.com/cpu": {value: "128"}
#   with that fixed: strict decoding error: unknown field "spec.devices[0].nodeAllocatableResources.mapping.cpu"   (gate off)
kubectl apply -f node-allocatable-overhead-slice.yaml --dry-run=server
#   strict decoding error: unknown field "spec.devices[0].nodeAllocatableResources.overhead.memory"
```

---

## Useful commands
```bash
kubectl get resourceclaim <c> -o jsonpath='{.status}' | jq .
kubectl get events --field-selector reason=BindingConditionsPending -A
```

## Cleanup
```bash
./cleanup.sh
```
