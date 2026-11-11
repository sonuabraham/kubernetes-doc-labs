# Volume Snapshot Classes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/volume-snapshot-classes/

> The docs' 2 blocks are **verbatim**: [01-volumesnapshotclass.yaml](01-volumesnapshotclass.yaml) and [02-volumesnapshotclass-default.yaml](02-volumesnapshotclass-default.yaml). Both are named `csi-hostpath-snapclass`, the class minikube's `csi-hostpath-driver` addon creates, so applying them **updates** the addon's class. [cleanup.sh](cleanup.sh) puts it back.

## Key ideas (read first)

| Field | Meaning |
|---|---|
| **VolumeSnapshotClass** | Cluster-scoped "class" for snapshots, the StorageClass of the snapshot world. A CRD, installed by the distribution with the snapshot controller. |
| **driver** | The CSI driver that takes the snapshots. **Required.** |
| **deletionPolicy** | **Required.** `Delete`: deleting the VolumeSnapshot deletes the content and backend snapshot. `Retain`: both stay. |
| **parameters** | Driver-specific (empty in the docs). Keys `csi.storage.k8s.io/snapshotter-secret-*` are read by the sidecar. |
| **Default class** | Annotation `snapshot.storage.kubernetes.io/is-default-class: "true"`. A VolumeSnapshot **without** a class uses the default **for the source PVC's driver**. Several defaults for one driver → snapshots are rejected. |
| **Immutable (by intent)** | The docs: "VolumeSnapshotClasses cannot be updated once created." |

---

## Step 1
```bash
cd concepts/storage/volume-snapshot-classes
kubectl apply -f 01-volumesnapshotclass.yaml        # "configured" - same as the addon's, nothing really changes
kubectl apply -f 00-setup.yaml                      # namespace vsc-demo, PVC src, class csi-hostpath-retain (Retain)
```

## Lab 1 – No default class
```bash
kubectl apply -f 03-snapshots.yaml                  # snap-noclass (no class) + snap-retain (class csi-hostpath-retain)
kubectl get volumesnapshot -n vsc-demo
#   snap-noclass                 src                                  <- stuck, no class
#   snap-retain    true   src   1Gi   csi-hostpath-retain   snapcontent-…
kubectl get volumesnapshot snap-noclass -n vsc-demo -o jsonpath='{.status.error.message}'
#   Failed to set default snapshot class with error cannot find default snapshot class
```

## Lab 2 – The default class (docs)
```bash
kubectl apply -f 02-volumesnapshotclass-default.yaml        # adds is-default-class: "true"
kubectl delete volumesnapshot snap-noclass -n vsc-demo ; kubectl apply -f 03-snapshots.yaml
kubectl get volumesnapshot -n vsc-demo -o custom-columns=NAME:.metadata.name,CLASS:.spec.volumeSnapshotClassName,READY:.status.readyToUse
#   snap-noclass   csi-hostpath-snapclass   true      <- filled in from the default for hostpath.csi.k8s.io
#   snap-retain    csi-hostpath-retain      true
```
Unlike PVCs, the existing stuck snapshot isn't retried with the new default. It was recreated here.

## Lab 3 – deletionPolicy
```bash
kubectl delete volumesnapshot --all -n vsc-demo
kubectl get volumesnapshotcontent -o custom-columns=NAME:.metadata.name,POLICY:.spec.deletionPolicy,REF:.spec.volumeSnapshotRef.name
#   snapcontent-3e49…   Retain   snap-retain        <- snap-noclass's content (Delete) is gone; this one stays
```
A retained content can be re-imported with a pre-provisioned VolumeSnapshot (see `../volume-snapshots`, Lab 2).

## Lab 4 – "Cannot be updated"… on this version
```bash
kubectl patch volumesnapshotclass csi-hostpath-retain --type=merge -p '{"driver":"other"}'
#   volumesnapshotclass.snapshot.storage.k8s.io/csi-hostpath-retain patched     <- accepted!
```
The addon's v6.1 CRD has **no immutability validation**, so the rule is a convention you have to follow yourself. (Newer external-snapshotter CRDs/webhooks enforce more.) Changing a class under existing snapshots can break their deletion.

---

## Useful commands
```bash
kubectl get volumesnapshotclass
kubectl get volumesnapshotclass -o custom-columns=NAME:.metadata.name,DRIVER:.driver,POLICY:.deletionPolicy,DEFAULT:.metadata.annotations.snapshot\\.storage\\.kubernetes\\.io/is-default-class
```

## Cleanup
```bash
./cleanup.sh       # namespace, Retain class + its contents; removes the default annotation from the addon's class again
```
