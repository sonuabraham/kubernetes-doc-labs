# Storage Capacity – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/storage-capacity/

> The page has no YAML. This lab uses minikube's `csi-hostpath-driver` addon (`minikube addons enable csi-hostpath-driver`), whose csi-provisioner already runs with `--enable-capacity`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Problem** | Without capacity info the scheduler may put a Pod on a node whose local/zonal storage can't hold its new volume. Provisioning then fails **after** scheduling. |
| **CSIStorageCapacity** | Namespaced objects (in the driver's namespace) published by external-provisioner: capacity per **StorageClass × topology segment** (`nodeTopology`), plus `maximumVolumeSize`. |
| **Opt-in** | `CSIDriver.spec.storageCapacity: true`. The scheduler then filters nodes by it. |
| **Scope** | Only **WaitForFirstConsumer** classes. Immediate binding happens before scheduling, so capacity can't help. Generic ephemeral volumes are covered too (they're PVCs). |
| **Rescheduling** | If provisioning still fails on the chosen node, the provisioner drops the `selected-node` annotation and the Pod is scheduled again. |
| **Limitations** | Data can be **stale**: two Pods may race for the last space. Multiple volumes per Pod are checked one at a time. Can't help a Pod already bound to a full node. |

---

## Step 1 – Capacity objects appear
```bash
cd concepts/storage/storage-capacity
kubectl get csidriver hostpath.csi.k8s.io -o jsonpath='{.spec.storageCapacity}'     # true
kubectl get csistoragecapacities -A                                                  # No resources found  (csi-hostpath-sc is Immediate)
kubectl apply -f 00-setup.yaml                                                       # class csi-hostpath-wffc (WaitForFirstConsumer)
kubectl get csistoragecapacities -A -o custom-columns=NS:.metadata.namespace,SC:.storageClassName,CAP:.capacity,MAX:.maximumVolumeSize,TOPO:.nodeTopology.matchLabels
#   kube-system   csi-hostpath-wffc   1Ti   1Ti   map[topology.hostpath.csi/node:minikube]      <- a few seconds later
```

## Lab 1 – The scheduler uses it
```bash
kubectl apply -f 01-too-big.yaml          # 2Ti claim + Pod
kubectl get events -n cap-demo --field-selector involvedObject.name=too-big,type=Warning -o custom-columns=M:.message
#   0/1 nodes are available: 1 node(s) did not have enough free storage.
kubectl get pvc too-big-claim -n cap-demo -o jsonpath='selected-node={.metadata.annotations.volume\.kubernetes\.io/selected-node}{"\n"}'
#   selected-node=           <- never handed to the driver
```

## Lab 2 – What it doesn't know
```bash
kubectl apply -f 02-fits.yaml ; kubectl wait --for=condition=Ready pod/fits -n cap-demo        # 600Gi - fine
kubectl get csistoragecapacities -n kube-system -o custom-columns=SC:.storageClassName,CAP:.capacity
#   csi-hostpath-wffc   1Ti            <- unchanged
kubectl apply -f 03-second.yaml           # another 600Gi → Running too (1.2Ti "used" of 1Ti)
```
Capacity is whatever the **driver reports** via `GetCapacity`. This hostpath driver (no `--capacity` flag) always reports its 1Ti maximum and never subtracts allocations, so the scheduler is only as good as that number. A real local-storage driver reports the free space left.

## Lab 3 – Without capacity tracking
```bash
kubectl patch csidriver hostpath.csi.k8s.io --type=merge -p '{"spec":{"storageCapacity":false}}'
kubectl delete -f 01-too-big.yaml ; kubectl apply -f 01-too-big.yaml
kubectl get pvc too-big-claim -n cap-demo -o jsonpath='selected-node={.metadata.annotations.volume\.kubernetes\.io/selected-node}{"\n"}'
#   selected-node=minikube        <- scheduled blindly
kubectl get events -n cap-demo --field-selector involvedObject.name=too-big-claim -o custom-columns=R:.reason,M:.message | tail -1
#   ProvisioningFailed  ... rpc error: code = OutOfRange desc = Requested capacity 2199023255552 exceeds maximum allowed 1099511627776
kubectl patch csidriver hostpath.csi.k8s.io --type=merge -p '{"spec":{"storageCapacity":true}}'
```
That's the failure capacity tracking exists to prevent: on a multi-node cluster the Pod would bounce between nodes (reschedule → provision → fail). With tracking, a node without room is filtered out up front.

---

## Useful commands
```bash
kubectl get csistoragecapacities -A
kubectl get csidriver -o custom-columns=NAME:.metadata.name,CAPACITY:.spec.storageCapacity
kubectl get pvc <p> -o jsonpath='{.metadata.annotations.volume\.kubernetes\.io/selected-node}'
```

## Cleanup
```bash
./cleanup.sh       # namespace, the WFFC class (its CSIStorageCapacity object goes too), storageCapacity back to true
```
