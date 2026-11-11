# Volume Snapshots – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/volume-snapshots/

> All 6 docs blocks are here **verbatim** (`01-` to `06-`). `05-` is the docs' `$ kubectl get crd …` line, which the page puts in a yaml fence. Runs on minikube's addons: `minikube addons enable volumesnapshots csi-hostpath-driver` (snapshot CRDs + snapshot-controller + class `csi-hostpath-snapclass`).

## Key ideas (read first)

| Object | Like… | Meaning |
|---|---|---|
| **VolumeSnapshot** | PVC | Namespaced *request* for a snapshot of a PVC, or a claim on an existing content |
| **VolumeSnapshotContent** | PV | Cluster-scoped: the actual snapshot on the storage system (`snapshotHandle`) |
| **VolumeSnapshotClass** | StorageClass | `driver`, `deletionPolicy`, parameters (see `../volume-snapshot-classes`) |

| Concept | Meaning |
|---|---|
| **Not core API** | CRDs + **snapshot-controller** (binding, lifecycle) + **csi-snapshotter** sidecar (talks to the driver), installed by the distribution. CSI drivers only. |
| **Dynamic** | VS with `source.persistentVolumeClaimName` + class → the controller creates content `snapcontent-<VS uid>`, and the driver cuts the snapshot. |
| **Pre-provisioned** | An admin creates content with `source.snapshotHandle` + `volumeSnapshotRef`. The VS uses `source.volumeSnapshotContentName`. This imports existing snapshots. |
| **Binding** | 1:1, using `volumeSnapshotRef` (with UID once bound) ↔ `status.boundVolumeSnapshotContentName`. |
| **Protection** | Finalizers: a PVC being snapshotted can't be deleted mid-snapshot; `volumesnapshot-as-source-protection` while a restore from it is in progress; `-bound-protection` on both. |
| **deletionPolicy** | `Delete`: deleting the VS removes the content and the backend snapshot. `Retain`: the content and data stay. |
| **Restore** | PVC `dataSource: {kind: VolumeSnapshot}` (see `../persistent-volumes`, Lab 7). |
| **Volume mode conversion** | With `--prevent-volume-mode-conversion`, restoring Filesystem → Block (or back) is refused unless the content has `snapshot.storage.kubernetes.io/allow-volume-mode-change: "true"`. Uses `sourceVolumeMode`. |
| **Topology** | Snapshots may only be restorable in some zones/nodes (driver-specific). |

---

## Step 1 – Source volume with data
```bash
cd concepts/storage/volume-snapshots
kubectl apply -f 00-setup.yaml          # namespace snap-demo, PVC pvc-test, Job writes "version-1"
kubectl wait --for=condition=Complete job/write-v1 -n snap-demo
```

## Lab 1 – Dynamic snapshot (docs `new-snapshot-test`)
```bash
kubectl apply -n snap-demo -f 01-volumesnapshot-dynamic.yaml
kubectl wait --for=jsonpath='{.status.readyToUse}'=true volumesnapshot/new-snapshot-test -n snap-demo
kubectl get volumesnapshot -n snap-demo
#   new-snapshot-test   true   pvc-test   1Gi   csi-hostpath-snapclass   snapcontent-3401a2d7-…
VSC=$(kubectl get volumesnapshot new-snapshot-test -n snap-demo -o jsonpath='{.status.boundVolumeSnapshotContentName}')
kubectl get volumesnapshotcontent $VSC -o jsonpath='{.spec.source} {.spec.deletionPolicy} ref={.spec.volumeSnapshotRef.namespace}/{.spec.volumeSnapshotRef.name} handle={.status.snapshotHandle}{"\n"}'
#   {"volumeHandle":"c639…"} Delete ref=snap-demo/new-snapshot-test handle=c840…    <- same shape as the docs' 03-… content
```
`spec.sourceVolumeMode` stays **empty** here. The addon's snapshot-controller v6.1 predates that field (see Lab 4).

## Lab 2 – Pre-provisioned snapshots (import an existing handle)
Both docs flows, pointed at the **real** handle of the snapshot from Lab 1:
```bash
H=$(kubectl get volumesnapshotcontent $VSC -o jsonpath='{.status.snapshotHandle}')
sed "s/SNAPSHOT_HANDLE/$H/" 07-test-content.yaml | kubectl apply -f -      # content test-content
kubectl apply -n snap-demo -f 02-volumesnapshot-preprovisioned.yaml         # docs test-snapshot → test-content
./import-content.sh                                                         # docs new-snapshot-content-test (adapted, see script)
kubectl apply -f 08-new-snapshot-test-default.yaml                          # default/new-snapshot-test → that content
kubectl get volumesnapshot -A
#   default     new-snapshot-test   true             new-snapshot-content-test   1Gi
#   snap-demo   new-snapshot-test   true   pvc-test                              1Gi   csi-hostpath-snapclass
#   snap-demo   test-snapshot       true             test-content                1Gi
```
Two minikube findings while doing this:
1. The docs' content as written is **rejected**: `strict decoding error: unknown field "spec.sourceVolumeMode"`. The addon installs the v6.1 snapshot CRDs, which don't have the field yet.
2. Imported contents never became ready until labelled `snapshot.storage.kubernetes.io/managed-by=minikube`. The addon runs csi-snapshotter with `--node-deployment`, and in that mode it only **watches** contents carrying its node's label. Dynamic contents get it automatically.

## Lab 3 – Restore both and compare
```bash
kubectl apply -f 09-restore.yaml ; kubectl wait --for=condition=Complete job/read-restored -n snap-demo
kubectl logs job/read-restored -n snap-demo
#   dynamic: version-1
#   imported: version-1          <- same backend snapshot, reached through two different API objects
```

## Lab 4 – Volume mode change annotation (docs)
```bash
kubectl apply -f 06-volumesnapshotcontent-allow-mode-change.yaml --dry-run=server
#   json: cannot unmarshal array into Go struct field ObjectMeta.metadata.annotations of type map[string]string
```
The docs block is **invalid**: its `annotations:` is a list (`- snapshot.storage…: "true"`) and must be a map:
```yaml
  annotations:
    snapshot.storage.kubernetes.io/allow-volume-mode-change: "true"
```

## Lab 5 – Deletion: Delete vs Retain
```bash
kubectl get volumesnapshot new-snapshot-test -n snap-demo -o jsonpath='{.metadata.finalizers}'
#   ["snapshot.storage.kubernetes.io/volumesnapshot-as-source-protection","snapshot.storage.kubernetes.io/volumesnapshot-bound-protection"]
kubectl delete job read-restored -n snap-demo ; kubectl delete pvc restored-dynamic -n snap-demo
kubectl delete volumesnapshot new-snapshot-test -n snap-demo
kubectl get volumesnapshotcontent $VSC              # NotFound   <- class policy Delete: content + backend snapshot gone
kubectl delete volumesnapshot test-snapshot -n snap-demo
kubectl get volumesnapshotcontent test-content      # still there, READY true   <- deletionPolicy Retain
```
The as-source protection only holds **while** a restore from the snapshot is in progress. Ours had finished, so the delete went straight through.

---

## Useful commands
```bash
kubectl get volumesnapshot,volumesnapshotcontent -A
kubectl get volumesnapshotclass
kubectl describe volumesnapshot <vs> -n <ns>       # events: SnapshotCreated, SnapshotReady, errors
kubectl get crd volumesnapshotcontents.snapshot.storage.k8s.io -o jsonpath='{.metadata.annotations}'   # CRD version
```

## Cleanup
```bash
./cleanup.sh       # default/new-snapshot-test, the namespace, and the Retain contents
```
