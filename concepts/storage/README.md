# Storage – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/

> Sub-pages, in a sensible order:
> [volumes](volumes/) → [persistent-volumes](persistent-volumes/) → [storage-classes](storage-classes/) → [dynamic-provisioning](dynamic-provisioning/) → [projected-volumes](projected-volumes/) → [ephemeral-volumes](ephemeral-volumes/) → [ephemeral-storage](ephemeral-storage/) → [volume-snapshots](volume-snapshots/) → [volume-snapshot-classes](volume-snapshot-classes/) → [volume-pvc-datasource](volume-pvc-datasource/) (cloning) → [volume-populators-and-data-sources](volume-populators-and-data-sources/) → [volume-attributes-classes](volume-attributes-classes/) → [storage-capacity](storage-capacity/) → [storage-limits](storage-limits/) → [volume-health-monitoring](volume-health-monitoring/) → [windows-storage](windows-storage/)

## Key ideas (read first)

| Layer | Objects | Who acts |
|---|---|---|
| **Pod** | `spec.volumes` + `volumeMounts` / `volumeDevices` | kubelet mounts at Pod start |
| **Claim** | PersistentVolumeClaim (namespaced) | user |
| **Class** | StorageClass, VolumeAttributesClass, VolumeSnapshotClass | admin |
| **Volume** | PersistentVolume (cluster-scoped) | provisioner / admin |
| **Snapshot** | VolumeSnapshot ↔ VolumeSnapshotContent (CRDs) | snapshot-controller + csi-snapshotter |
| **Driver** | CSIDriver, CSINode, VolumeAttachment, CSIStorageCapacity | CSI driver + sidecars (provisioner, attacher, resizer, snapshotter, health-monitor) |

## The minikube setup used throughout
Most sub-labs need a real CSI driver:
```bash
minikube addons enable volumesnapshots
minikube addons enable csi-hostpath-driver    # driver hostpath.csi.k8s.io, class csi-hostpath-sc, snapclass csi-hostpath-snapclass
```
Its components are **old** (hostpathplugin v1.9, csi-provisioner v3.3, csi-resizer v1.6, snapshot CRDs/controller v6.1), and that shows in a few labs:

| Lab | Effect |
|---|---|
| [volume-attributes-classes](volume-attributes-classes/) | the provisioner drops `volumeAttributesClassName`, so provisioning fails; there's no modify support |
| [volume-snapshots](volume-snapshots/) | CRDs lack `sourceVolumeMode`; imported contents need the `managed-by` label |
| [persistent-volumes](persistent-volumes/) | Block mode provisions, but mapping fails (no loop devices in the docker-driver node) |
| [storage-capacity](storage-capacity/) | capacity is a fixed 1Ti and never decreases |

The default class `standard` (`k8s.io/minikube-hostpath`) is **not CSI** and silently ignores `dataSource`/`dataSourceRef` (see [cloning](volume-pvc-datasource/) and [populators](volume-populators-and-data-sources/)).

---

## Lab – Follow one volume through every layer
```bash
cd concepts/storage
kubectl apply -f 00-storage-stack.yaml ; kubectl wait --for=condition=Ready pod/app -n storage-demo
PV=$(kubectl get pvc data -n storage-demo -o jsonpath='{.spec.volumeName}')
kubectl get pvc data -n storage-demo -o custom-columns=PVC:.metadata.name,CLASS:.spec.storageClassName,PV:.spec.volumeName
#   data   csi-hostpath-sc   pvc-b2c3cc8c-…                       <- claim → class → PV
kubectl get sc csi-hostpath-sc -o custom-columns=CLASS:.metadata.name,PROVISIONER:.provisioner
#   csi-hostpath-sc   hostpath.csi.k8s.io                        <- class → driver
kubectl get pv $PV -o custom-columns=PV:.metadata.name,DRIVER:.spec.csi.driver,HANDLE:.spec.csi.volumeHandle
#   pvc-b2c3…   hostpath.csi.k8s.io   9d308566-de2d-…            <- PV → the driver's own volume ID
kubectl get csidriver hostpath.csi.k8s.io -o custom-columns=DRIVER:.metadata.name,ATTACH:.spec.attachRequired,MODES:.spec.volumeLifecycleModes
#   hostpath.csi.k8s.io   false   [Persistent Ephemeral]        <- attachRequired false → no VolumeAttachment
kubectl get csinode minikube -o jsonpath='{.spec.drivers[*].name}{"\n"}'     # hostpath.csi.k8s.io   (node plugin registered here)
kubectl get volumeattachments                                                 # No resources found
UID_=$(kubectl get pod app -n storage-demo -o jsonpath='{.metadata.uid}')
minikube ssh -- "sudo ls /var/lib/kubelet/pods/$UID_/volumes/kubernetes.io~csi/"    # pvc-b2c3…   <- the kubelet's mount point for this Pod
kubectl exec app -n storage-demo -- sh -c 'mount | grep /data'                    # … on /data type ext4      <- what the container sees
```
On a cloud block-storage driver (`attachRequired: true`) you'd also see a **VolumeAttachment** (PV ↔ node), created by the attach/detach controller and fulfilled by csi-attacher, before the kubelet mounts.

---

## Useful commands
```bash
kubectl get sc,pvc,pv -A
kubectl get csidriver,csinode,volumeattachments
kubectl get volumesnapshot,volumesnapshotcontent,volumesnapshotclass -A
kubectl describe pvc <p>          # events explain Pending claims
```

## Cleanup
```bash
./cleanup.sh       # this lab; see the script for removing the CSI addons
```
