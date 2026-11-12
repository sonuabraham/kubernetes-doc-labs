# Dynamic Resource Allocation – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/

> Sub-pages: [dra-api](dra-api/), [how-dra-works](how-dra-works/), [dra-observability](dra-observability/), [dra-features](dra-features/), [device-taints](device-taints/).
>
> Real DRA needs a vendor **driver** (a DaemonSet that publishes ResourceSlices and prepares devices). Instead of installing one, these labs use **[fake-dra.sh](fake-dra.sh)**: two fake nodes (`../../scheduling-eviction/fake-nodes.sh`) with **hand-published ResourceSlices** for a pretend driver `gpu.example.com` (fake-1: 2 × a100 40Gi, fake-2: 2 × h100 80Gi) and a DeviceClass. The **scheduler allocates them for real**. What can't happen is the node-side *prepare* step, so Pods stay Pending on their node and the labs read `ResourceClaim.status`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Why DRA** | Devices richer than "a count" (`nvidia.com/gpu: 1`): select by **attributes** (model, memory, driver version) with CEL, share devices, configure them, partition them. GA in v1.34+. |
| **Objects** | **DeviceClass** (admin: what counts as "a GPU"), **ResourceClaim** (a request for devices), **ResourceClaimTemplate** (one claim per Pod), **ResourceSlice** (driver: the devices on a node). |
| **Who does what** | Cluster admin: driver + DeviceClasses. Workload operator: claims and templates. Driver author: slices, prepare/unprepare. |
| **Scheduling** | The scheduler finds devices matching **all** requests on a node and writes the allocation into the claim's status; the Pod goes to that node. |
| **Limitations** | Only the scheduler's allocation counts (no "manual" allocation in the normal path). Device plugins and DRA coexist. Some features are still alpha/beta (see dra-features). |

---

## Step 1
```bash
cd concepts/resource-management/dynamic-resource-allocation
./fake-dra.sh up
#   fake-1-gpu.example.com  fake-1  gpu-0,gpu-1
#   fake-2-gpu.example.com  fake-2  gpu-0,gpu-1
kubectl apply -f 01-claims.yaml     # namespace dra-demo, template one-gpu, claim shared-h100 (CEL: model == "h100")
```

## Lab 1 – One claim, two Pods (sharing)
```bash
./pod.sh share-1 claim shared-h100 ; ./pod.sh share-2 claim shared-h100
kubectl get pods -n dra-demo -o wide                  # both on fake-2 (where the h100s are)
kubectl get resourceclaim shared-h100 -n dra-demo -o jsonpath='{.status.allocation.devices.results} reservedFor={.status.reservedFor[*].name}'
#   [{"device":"gpu-0","driver":"gpu.example.com","pool":"fake-2","request":"gpu"}] reservedFor=share-1 share-2
```

## Lab 2 – A claim per Pod (template)
```bash
for i in 1 2 3; do ./pod.sh own-$i template one-gpu; done
kubectl get resourceclaims -n dra-demo -o custom-columns=CLAIM:.metadata.name,DEVICE:.status.allocation.devices.results[0].device,POOL:.status.allocation.devices.results[0].pool,OWNER:.metadata.ownerReferences[0].name
#   own-1-gpu-vj9k2   gpu-0   fake-1   own-1      <- generated claim, owned by the Pod (deleted with it)
#   own-2-gpu-xt2gw   gpu-1   fake-1   own-2
#   own-3-gpu-4rvbv   gpu-1   fake-2   own-3
#   shared-h100       gpu-0   fake-2   <none>
./pod.sh own-4 template one-gpu
#   0/3 nodes are available: 3 cannot allocate all claims.          <- all 4 devices taken
```

---

## Useful commands
```bash
kubectl get deviceclasses,resourceslices
kubectl get resourceclaims,resourceclaimtemplates -A
kubectl get resourceclaim <c> -o jsonpath='{.status.allocation}' | jq .
```

## Cleanup
```bash
./cleanup.sh              # dra-demo; ./fake-dra.sh down after the sub-labs
```
