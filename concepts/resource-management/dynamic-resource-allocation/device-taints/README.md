# DRA Device Taints and Tolerations – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/device-taints/

> The docs' DeviceTaintRule is **verbatim** in [devicetaintrule-example.yaml](devicetaintrule-example.yaml) (taints every device of driver `dra.example.com`, NoExecute). [00-setup.yaml](00-setup.yaml) publishes two `dra.example.com` devices on fake-1, one of them **tainted by the "driver"** in its ResourceSlice. Fake nodes: `../fake-dra.sh up`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Device taint** | Like node taints, but per **device**: `key`, `value`, `effect` = `NoSchedule` (don't allocate), `NoExecute` (also **evict** Pods using it), `None` (informational / dry-run). |
| **Set by the driver** | In the ResourceSlice (`devices[].taints`), e.g. health problems. |
| **Set by an admin** | `DeviceTaintRule`: `deviceSelector` (driver, pool, device) + taint, without touching the driver's slices. Status reports eviction progress. |
| **Tolerations** | In the **claim** request (`exactly.tolerations`), not the Pod. `tolerationSeconds` for NoExecute. |
| **Eviction** | The device taint eviction controller deletes Pods whose allocated devices carry an untolerated NoExecute taint. |

---

## Step 1
```bash
cd concepts/resource-management/dynamic-resource-allocation/device-taints
../fake-dra.sh up ; kubectl apply -f 00-setup.yaml       # dev-ok, dev-degraded (NoSchedule, dra.example.com/degraded=ecc-errors)
```

## Lab 1 – Driver-set NoSchedule
```bash
# claims a, b without tolerations; c tolerating dra.example.com/degraded:
#   a   dev-ok
#   b   <none>          "0/3 nodes are available: 3 cannot allocate all claims"   <- dev-degraded is off-limits
#   c   dev-degraded    <- the claim's toleration lets it use the tainted device
```

## Lab 2 – Admin DeviceTaintRule, NoExecute (docs)
```bash
kubectl apply -f devicetaintrule-example.yaml
kubectl get events -n dra-taint -o custom-columns=OBJ:.involvedObject.name,R:.reason,M:.message | grep -i evict
#   a   DeviceTaintManagerEviction   Marking for deletion
#   c   DeviceTaintManagerEviction   Marking for deletion        <- c tolerated "degraded", not "unhealthy"
kubectl get devicetaintrule example -o jsonpath='{.status}' | jq -c .
#   {"conditions":[{"message":"2 pods need to be evicted in 1 namespace.","reason":"PodsPendingEviction","status":"True","type":"EvictionInProgress"}]}
```
On fake nodes the Pods stay `Terminating` (no kubelet), so the rule keeps reporting "in progress". A real cluster would finish.

## Lab 3 – Preview with effect None
```bash
kubectl apply -f 01-preview-rule.yaml          # all gpu.example.com devices
kubectl get devicetaintrule preview -o jsonpath='{.status.conditions[0].message}'
#   4 published devices selected. 0 allocated devices selected. 0 pods would be evicted in 0 different namespaces
#   if the effect was NoExecute. This information will not be updated again. Recreate the DeviceTaintRule to trigger an update.
```
Run this before a maintenance taint to see the blast radius.

---

## Useful commands
```bash
kubectl get devicetaintrules
kubectl get resourceslices -o json | jq '.items[].spec.devices[] | select(.taints) | {name, taints}'
```

## Cleanup
```bash
./cleanup.sh          # then  ../fake-dra.sh down  when you're done with DRA
```
