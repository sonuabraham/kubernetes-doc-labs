# Persistent Volumes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/persistent-volumes/

> All 13 YAML blocks from the page are here **verbatim** (`01-…` to `13-…`). `02`/`03` contain the docs' literal `...`, so they're excerpts; [16-reserve-foo-filled.yaml](16-reserve-foo-filled.yaml) is the runnable version. Files `14-`… and [00-setup.yaml](00-setup.yaml) supply what the docs objects refer to by name: class `slow`, namespace `foo`, VolumeSnapshot `new-snapshot-test`, PVC `existing-src-pvc-name`, class `my-csi-plugin`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **PersistentVolume (PV)** | Cluster-scoped piece of storage, provisioned by an admin (**static**) or by a StorageClass (**dynamic**). Lifecycle independent of Pods. |
| **PersistentVolumeClaim (PVC)** | Namespaced *request* for storage: size, access modes, class, optional selector. Pods use claims, not PVs. |
| **Binding** | 1:1 and exclusive (`claimRef`). A claim may get a **bigger** PV than asked. No match → stays `Pending` until one appears. |
| **Storage Object in Use Protection** | Finalizers `kubernetes.io/pvc-protection` / `pv-protection`: a PVC used by a Pod (or a bound PV) is only removed once unused. |
| **Reclaim policy** | `Retain` → PV becomes `Released` and keeps data, admin cleans up. `Delete` → PV + backing storage deleted. `Recycle` (**deprecated**) → `rm -rf` by a recycler Pod, PV back to `Available`. |
| **PV deletion protection finalizer** | `external-provisioner.volume.kubernetes.io/finalizer` (CSI) / `kubernetes.io/pv-controller`: honour `Delete` even if the PV is deleted before the PVC (`HonorPVReclaimPolicy`, stable). |
| **Reserving a PV** | PV `claimRef` + PVC `volumeName` (with `storageClassName: ""`) pre-bind a specific pair. |
| **Expansion** | `allowVolumeExpansion: true` in the class → edit the PVC's request. Online for in-use volumes (CSI). Shrinking is forbidden. `RecoverVolumeExpansionFailure` (stable) lets you lower a failed request. |
| **volumeMode** | `Filesystem` (default, mounted) or `Block` (raw device via `volumeDevices`/`devicePath`). |
| **Access modes** | `RWO` (one node), `ROX`, `RWX`, `RWOP` (one Pod, CSI only). Used for **matching**, not enforcement (except RWOP). |
| **Phases** | `Available`, `Bound`, `Released`, `Failed`, plus `status.lastPhaseTransitionTime`. |
| **Class** | `storageClassName` must match. `""` = no class. **Unset** = the default class is filled in (also retroactively). |
| **Unused PVC tracking** | Condition `Unused=True` when no Pod uses the claim (`PersistentVolumeClaimUnusedSinceTime`, beta). |
| **Data sources** | `dataSource` / `dataSourceRef`: VolumeSnapshot (restore), PVC (clone), any CR via a **volume populator**. |
| **Mutable PV nodeAffinity** | `MutablePVNodeAffinity` (alpha, off here). |

## The demo app
Uses minikube's CSI addons for everything dynamic:
```bash
minikube addons enable volumesnapshots
minikube addons enable csi-hostpath-driver      # class csi-hostpath-sc + snapclass csi-hostpath-snapclass
```
[00-setup.yaml](00-setup.yaml): namespaces `pv-demo` and `foo`, a static hostPath PV `task-pv-volume` (class `manual`, Retain), two PVs in class `slow` (`pv-stable-dev`, `pv-stable-prod`) for the docs' selector claim, and classes `csi-expandable` (with expansion) and `my-csi-plugin`, both on `hostpath.csi.k8s.io`.

---

## Step 1
```bash
cd concepts/storage/persistent-volumes
kubectl apply -f 00-setup.yaml
```

## Lab 1 – Static binding and in-use protection
```bash
kubectl apply -f 14-task-pvc-pod.yaml ; kubectl wait --for=condition=Ready pod/task-pv-pod -n pv-demo
kubectl get pvc task-pv-claim -n pv-demo
#   task-pv-claim   Bound   task-pv-volume   1Gi   RWO   manual        <- asked 500Mi, got the whole 1Gi PV
kubectl delete pvc task-pv-claim -n pv-demo --wait=false
kubectl describe pvc task-pv-claim -n pv-demo | grep -E 'Status|Finalizers'
#   Status:        Terminating
#   Finalizers:    [kubernetes.io/pvc-protection]      <- still used by task-pv-pod, so not removed
kubectl get pv task-pv-volume -o jsonpath='{.metadata.finalizers}'      # ["kubernetes.io/pv-protection"]
kubectl delete pod task-pv-pod -n pv-demo                                # now the PVC disappears
```

## Lab 2 – Retain: Released, data kept, manual reuse
```bash
kubectl get pv task-pv-volume -o custom-columns=STATUS:.status.phase,CLAIM:.spec.claimRef.name,RECLAIM:.spec.persistentVolumeReclaimPolicy,LAST:.status.lastPhaseTransitionTime
#   Released   task-pv-claim   Retain   2026-11-11T22:12:07Z
minikube ssh -- cat /tmp/data/msg                      # hello-from-task-pv-pod   <- data survived
kubectl apply -f 14-task-pvc-pod.yaml ; kubectl get pvc task-pv-claim -n pv-demo
#   Pending      <- a Released PV is NOT re-bound (it still has the old claimRef)
kubectl patch pv task-pv-volume --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
kubectl get pvc task-pv-claim -n pv-demo               # Bound   <- admin "made it Available" again
kubectl delete pod task-pv-pod -n pv-demo
kubectl get pvc task-pv-claim -n pv-demo -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
#   Unused=True NoPodsUsingPVC            <- unused PVC tracking
```
While Pending, the claim's events show `storageclass.storage.k8s.io "manual" not found`. A claim's class is just a matching label; the class object doesn't have to exist for static binding.

## Lab 3 – Recycle (deprecated)
```bash
kubectl apply -f 05-pv0003-nfs.yaml
#   Warning: spec.persistentVolumeReclaimPolicy: The Recycle reclaim policy is deprecated. ...
kubectl apply -f 15-recycle-hostpath.yaml              # same policy on hostPath (pv0003's NFS server doesn't exist)
minikube ssh -- "sudo mkdir -p /tmp/recycle-pv && sudo sh -c 'echo secret > /tmp/recycle-pv/old-data; touch /tmp/recycle-pv/.hidden'"
kubectl delete pvc recycle-claim -n pv-demo
kubectl wait --for=jsonpath='{.status.phase}'=Available pv/recycle-pv
minikube ssh -- "ls -A /tmp/recycle-pv | wc -l"        # 0   <- scrubbed, including dotfiles
kubectl get events -A --field-selector involvedObject.name=recycle-pv -o custom-columns=R:.reason,M:.message
#   RecyclerPod   Recycler pod: Successfully assigned default/recycler-for-recycle-pv to minikube
#   VolumeRecycled  Volume recycled
```
[01-pv-recycler.yaml](01-pv-recycler.yaml) is the docs' *custom* recycler template. It only takes effect when passed to kube-controller-manager with `--pv-recycler-pod-template-filepath-hostpath`. The built-in one used a `debian-base` image here.

## Lab 4 – Reserving a PV, selectors
```bash
kubectl apply -f 16-reserve-foo-filled.yaml
kubectl get pvc -n foo
#   foo-pvc   Bound     foo-pv
#   thief     Pending          <- same size/mode/class, but foo-pv's claimRef reserves it for foo/foo-pvc
kubectl apply -n pv-demo -f 06-myclaim-selector.yaml -f 07-mypod.yaml
kubectl get pv pv-stable-dev pv-stable-prod pv0003
#   pv-stable-dev    10Gi  Bound      pv-demo/myclaim   slow     <- release=stable AND environment in (dev)
#   pv-stable-prod   10Gi  Available                    slow     <- environment=prod: selector says no
#   pv0003           5Gi   Available                    slow     <- too small for 8Gi, no labels
```

## Lab 5 – Expanding a claim (in use)
```bash
kubectl apply -f 04-storageclass-allow-expansion.yaml   # docs class; its provisioner is fictional, shown for the field only
kubectl apply -f 17-expand-pvc-pod.yaml ; kubectl wait --for=condition=Ready pod/grow-pod -n pv-demo
kubectl patch pvc grow-pvc -n pv-demo -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
kubectl wait --for=jsonpath='{.status.capacity.storage}'=2Gi pvc/grow-pvc -n pv-demo
kubectl get events -n pv-demo --field-selector involvedObject.name=grow-pvc -o custom-columns=R:.reason
#   ExternalExpanding → Resizing (controller side, csi-resizer) → FileSystemResizeSuccessful (kubelet, NodeExpandVolume)
kubectl patch pvc grow-pvc -n pv-demo -p '{"spec":{"resources":{"requests":{"storage":"1Gi"}}}}'
#   Forbidden: field can not be less than status.capacity
kubectl patch pvc fixed-pvc -n pv-demo -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
#   Forbidden: only dynamically provisioned pvc can be resized and the storageclass that provisions the pvc must support resize
```
The hostpath CSI driver backs volumes with plain directories, so `df /data` shows the node disk before and after. Size here is bookkeeping. On a real block-backed driver the filesystem grows.

## Lab 6 – Raw block volumes
```bash
kubectl apply -f 08-block-pv-fc.yaml                    # Available - a Fibre Channel PV; no FC SAN, but the API object is fine
kubectl apply -n pv-demo -f 09-block-pvc.yaml -f 10-pod-with-block-volume.yaml
kubectl get pvc block-pvc -n pv-demo -o wide
#   block-pvc   Pending   standard   Block        <- the DEFAULT class was filled in, so it can't match block-pv (class "")
#   event: k8s.io/minikube-hostpath does not support block volume provisioning
```
That's the "unset class = default class" rule. To bind the docs pair you'd need `storageClassName: ""` on the claim. With a Block-capable CSI class instead:
```bash
kubectl delete pod pod-with-block-volume -n pv-demo --force ; kubectl delete pvc block-pvc -n pv-demo
kubectl apply -n pv-demo -f 18-block-pvc-csi.yaml -f 10-pod-with-block-volume.yaml
kubectl get pvc block-pvc -n pv-demo -o wide            # Bound ... csi-hostpath-sc   Block
kubectl describe pod pod-with-block-volume -n pv-demo | tail -1
#   FailedMapVolume  MapVolume.MapBlockVolume failed ... makeLoopDevice failed ... losetup -f ... exit status 1
```
Provisioning and binding in Block mode work. Handing the device to the container doesn't **on minikube's docker driver**: the node container has no free loop devices. On a VM or real node, `/dev/xvda` appears in the container as a block device with no filesystem.

## Lab 7 – Restore from a VolumeSnapshot
```bash
kubectl apply -n pv-demo -f 19-snapshot-clone-sources.yaml      # writer pod + VolumeSnapshot new-snapshot-test
kubectl wait --for=jsonpath='{.status.readyToUse}'=true volumesnapshot/new-snapshot-test -n pv-demo
kubectl get volumesnapshot -n pv-demo
#   new-snapshot-test   true   snap-src-pvc   1Gi   csi-hostpath-snapclass   snapcontent-…
kubectl apply -n pv-demo -f 11-restore-pvc-from-snapshot.yaml   # docs restore-pvc (10Gi from a 1Gi snapshot - bigger is OK)
```

## Lab 8 – Clone, then read both
```bash
kubectl apply -n pv-demo -f 12-cloned-pvc.yaml                  # docs cloned-pvc ← PVC existing-src-pvc-name
kubectl apply -n pv-demo -f 20-reader.yaml ; kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/reader -n pv-demo
kubectl logs reader -n pv-demo
#   restore: data-at-snapshot-time
#   clone: data-in-source-pvc
```

## Lab 9 – Volume populators (dataSourceRef)
```bash
kubectl apply -n pv-demo -f 13-populated-pvc.yaml
kubectl get pvc populated-pvc -n pv-demo -o jsonpath='{.status.phase} dataSource={.spec.dataSource}{"\n"}'
#   Bound dataSource={"apiGroup":"example.storage.k8s.io","kind":"ExampleDataSource","name":"example-name"}
```
The API mirrored `dataSourceRef` into `dataSource` and accepted a kind that doesn't exist. Then the **default** provisioner (`k8s.io/minikube-hostpath`, not CSI) **ignored the data source** and provisioned an empty volume. A compliant provisioner leaves the claim Pending for a populator. See `../volume-populators-and-data-sources`.

---

## Useful commands
```bash
kubectl get pv,pvc -A
kubectl get pv -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.namespace/.spec.claimRef.name,RECLAIM:.spec.persistentVolumeReclaimPolicy
kubectl describe pvc <name>          # events explain Pending
kubectl get volumesnapshot,volumesnapshotcontent -A
```

## Cleanup
```bash
./cleanup.sh       # namespaces, static PVs, extra classes, node dirs (keeps the CSI addons for the next labs)
```
