# Node-specific Volume Limits – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/storage-limits/

> The docs' 2 blocks are **verbatim**: [01-csidriver-update-period.yaml](01-csidriver-update-period.yaml) and [02-csidriver-prevent-scheduling.yaml](02-csidriver-prevent-scheduling.yaml). They're partial `CSIDriver` objects for `hostpath.csi.k8s.io`, so on a cluster where that driver exists they're applied as **patches** (see Step 1). Uses minikube's `csi-hostpath-driver` addon.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Why** | Clouds cap attached disks per VM. If the scheduler ignores that, Pods land on full nodes and hang in `ContainerCreating`. |
| **Default in-tree limits** | EBS 39, GCE PD 16, Azure Disk 16. Dynamic per instance type (e.g. EBS on Nitro: 25, GCE up to 127, Azure up to 64). |
| **CSI** | The node plugin reports `max_volumes_per_node` in `NodeGetInfo` → kubelet writes `CSINode.spec.drivers[].allocatable.count` → the scheduler's **NodeVolumeLimits** plugin counts the CSI volumes in use per driver and node. Migrated in-tree volumes use the CSI driver's number. |
| **MutableCSINodeAllocatableCount** (on in v1.37) | `allocatable.count` may change. `CSIDriver.spec.nodeAllocatableUpdatePeriodSeconds` (≥ 10) makes the kubelet re-query `NodeGetInfo` periodically. A `ResourceExhausted` attach error triggers an immediate refresh and **fails** the affected Pods so controllers recreate them. |
| **preventPodSchedulingIfMissing** (`VolumeLimitScaling`, beta, on) | `true` → don't schedule a Pod onto a node whose CSINode doesn't list the driver. Default `false` for compatibility with Cluster Autoscaler (only enable it there with `--enable-csi-node-aware-scheduling=true`). |

---

## Step 1 – The docs' CSIDriver snippets
```bash
cd concepts/storage/storage-limits
kubectl apply -f 01-csidriver-update-period.yaml --dry-run=server
#   The CSIDriver "hostpath.csi.k8s.io" is invalid:
#   * spec.attachedRequired: Invalid value: true: field is immutable
#   * spec.volumeLifecycleModes: Invalid value: ["Persistent"]: field is immutable
```
As whole objects they'd reset the addon driver's other fields to their defaults (`attachRequired: true`, `Persistent` only), which are immutable. Apply just the field:
```bash
kubectl patch csidriver hostpath.csi.k8s.io --type=merge -p '{"spec":{"nodeAllocatableUpdatePeriodSeconds":60}}'   # used in Lab 2
```

## Lab 1 – The scheduler counts CSI volumes
```bash
kubectl get csinode minikube -o jsonpath='{.spec.drivers[0]}{"\n"}'
#   {"name":"hostpath.csi.k8s.io","nodeID":"minikube","topologyKeys":[...]}      <- no allocatable: driver reports no limit
kubectl patch csinode minikube --type=json -p '[{"op":"add","path":"/spec/drivers/0/allocatable","value":{"count":2}}]'
#   pretend the node can hold 2 volumes of this driver (normally the kubelet sets this)
kubectl apply -f 03-three-pods.yaml
kubectl get pods -n limits-demo
#   app-1  Running   app-2  Running   app-3  Pending
kubectl get events -n limits-demo --field-selector involvedObject.name=app-3,reason=FailedScheduling -o custom-columns=M:.message | tail -1
#   0/1 nodes are available: 1 node(s) exceed max volume count.
kubectl patch csinode minikube --type=json -p '[{"op":"replace","path":"/spec/drivers/0/allocatable/count","value":5}]'
kubectl get pods -n limits-demo        # app-3 Running   (count is mutable; the scheduler retried)
```

## Lab 2 – Periodic refresh from the driver (docs `nodeAllocatableUpdatePeriodSeconds`)
```bash
kubectl patch csidriver hostpath.csi.k8s.io --type=merge -p '{"spec":{"nodeAllocatableUpdatePeriodSeconds":5}}'
#   Invalid value: 5: must be greater than or equal to 10 seconds
# with 60 (Step 1) set, wait a minute or so:
kubectl get csinode minikube -o jsonpath='{.spec.drivers[0].allocatable}{"\n"}'
#   (empty)        <- ~70s later the kubelet called NodeGetInfo; the driver reports 0 = unlimited, so our manual "5" is gone
```
CSINode is **kubelet-owned**. With periodic updates on, the kubelet keeps it in line with what the driver says.

## Lab 3 – preventPodSchedulingIfMissing (docs `02-…`)
[04-missing-driver.yaml](04-missing-driver.yaml): a CSIDriver `absent.csi.example.com` whose node plugin runs nowhere, plus a PV, claim and Pod for it.
```bash
kubectl apply -f 04-missing-driver.yaml          # preventPodSchedulingIfMissing: false
kubectl get pod needs-absent-driver -n limits-demo -o wide
#   ContainerCreating   minikube        <- scheduled anyway, then:
#   MountVolume.MountDevice failed ... driver name absent.csi.example.com not found in the list of registered CSI drivers
kubectl delete pod needs-absent-driver -n limits-demo --force
kubectl patch csidriver absent.csi.example.com --type=merge -p '{"spec":{"preventPodSchedulingIfMissing":true}}'
sed -n '/^kind: Pod/,$p' 04-missing-driver.yaml | sed '1i apiVersion: v1' | kubectl apply -f -
kubectl get events -n limits-demo --field-selector involvedObject.name=needs-absent-driver,reason=FailedScheduling -o custom-columns=M:.message | tail -1
#   0/1 nodes are available: 1 absent.csi.example.com CSI driver is not installed on the node.
```
Pending with a clear reason is better than stuck on a node that can never mount the volume. On a mixed cluster the scheduler simply picks a node that has the driver.

---

## Useful commands
```bash
kubectl get csinode -o custom-columns=NODE:.metadata.name,DRIVERS:.spec.drivers[*].name,LIMITS:.spec.drivers[*].allocatable.count
kubectl get csidriver -o custom-columns=NAME:.metadata.name,PERIOD:.spec.nodeAllocatableUpdatePeriodSeconds,PREVENT:.spec.preventPodSchedulingIfMissing
kubectl get volumeattachments
```

## Cleanup
```bash
./cleanup.sh       # namespace, fake driver + PV, undo the CSIDriver/CSINode patches
```
