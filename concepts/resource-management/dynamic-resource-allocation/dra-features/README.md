# DRA Features – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/dra-features/

> The docs' 7 blocks are **verbatim** (descriptive names; the two `*-status-excerpt.yaml` contain `...`). Their slices target `nodeName: worker-1`, which this lab rewrites to the fake node `fake-1` (`sed 's/worker-1/fake-1/'`). Fake nodes come from `../fake-dra.sh up`. [00-setup.yaml](00-setup.yaml) adds the DeviceClasses the docs assume.

## Key ideas (read first)

| Feature | Gate here | Meaning |
|---|---|---|
| **Partitionable devices** | beta, on | `sharedCounters` (e.g. a GPU's 8Gi) + devices that `consumesCounters` (MIG-like partitions). Partitions can't oversubscribe the shared counter. |
| **Device compatibility groups** | alpha, **off** | Partitions of different "kinds" (MIG vs vGPU) mustn't coexist on one physical device. |
| **Consumable capacity** | beta, on | `allowMultipleAllocations: true` + `capacity.<name>.requestPolicy` (default, validRange/validValues). Many claims share one device, each consuming part (`consumedCapacity`, unique `shareID`). |
| **Granular status authorization** | beta, on | See `../../../security/hardening-guide/dynamic-resource-allocation`. |
| **Optional node operations** | alpha, **off** | `skipNodeOperations` for devices that need no kubelet prepare (control-plane-only resources). |

---

## Step 1
```bash
cd concepts/resource-management/dynamic-resource-allocation/dra-features
../fake-dra.sh up ; kubectl apply -f 00-setup.yaml
```

## Lab 1 – Partitionable devices (docs countersets)
```bash
sed 's/worker-1/fake-1/' partitionable-countersets-slices.yaml | kubectl apply -f -
# claims part-1, part-2 (class dra.example.com), Pods pinned to fake-1:
#   part-1   device-1          <- 6Gi of the 8Gi counter
#   part-2   <none>            "cannot allocate all claims": device-2 also needs 6Gi, only 2Gi left
```

## Lab 2 – Consumable capacity (docs slice + template)
```bash
sed 's/worker-1/fake-1/' consumable-capacity-slice.yaml | kubectl apply -f -      # eth1: 10G bandwidth, allowMultipleAllocations
kubectl apply -n dra-feat -f bandwidth-claim-template.yaml                        # 1G each
# Pods bw-1..3 using the template:
#   bw-1-r-…   eth1   map[bandwidth:1G]   d646e39b-…       <- same device, three claims,
#   bw-2-r-…   eth1   map[bandwidth:1G]   e52d26a7-…          each with its own shareID
#   bw-3-r-…   eth1   map[bandwidth:1G]   6ad16012-…
# claim big-bw (8G): "cannot allocate all claims"   (3G used + 8G > 10G)
# claim round-bw (1000001):  consumed={"bandwidth":"1000008"}   <- rounded UP to min 1M + a multiple of step 8
```
The status matches the docs' [consumed-capacity-status-excerpt.yaml](consumed-capacity-status-excerpt.yaml).

## Lab 3 – Alpha features (off): dropped, not rejected
```bash
sed 's/worker-1/fake-1/' compatibility-groups-slices.yaml | kubectl apply --dry-run=server -f - -o json | jq -c '.items[1].spec.devices[0].consumesCounters[0]'
#   {"counterSet":"gpu-0-memory","counters":{"memory":{"value":"4Gi"}}}          <- compatibilityGroups gone
sed 's/worker-1/fake-1/' skip-node-operations-slice.yaml | kubectl apply --dry-run=server -f - -o jsonpath='{.spec}'
#   {"devices":[{"name":"virtual-device-1"}],"driver":"control-plane.example.com",...}   <- skipNodeOperations gone
```
Both are accepted as "created". The alpha fields are silently stripped, so the MIG/vGPU partitions could be mixed and the kubelet would still try to prepare `virtual-device-1`.

---

## Useful commands
```bash
kubectl get resourceclaims -n dra-feat -o custom-columns=CLAIM:.metadata.name,DEVICE:.status.allocation.devices.results[*].device,CONSUMED:.status.allocation.devices.results[*].consumedCapacity,SHARE:.status.allocation.devices.results[*].shareID
kubectl get resourceslices -o json | jq '.items[] | {name: .metadata.name, counters: .spec.sharedCounters}'
```

## Cleanup
```bash
./cleanup.sh
```
