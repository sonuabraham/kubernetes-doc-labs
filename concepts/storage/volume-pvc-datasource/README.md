# CSI Volume Cloning – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/volume-pvc-datasource/

> The docs manifest is **verbatim**: [01-clone-of-pvc-1.yaml](01-clone-of-pvc-1.yaml) (`clone-of-pvc-1` in `myns`, class `cloning`, from `pvc-1`). [00-setup.yaml](00-setup.yaml) creates what it names: namespace `myns`, class `cloning` on minikube's `csi-hostpath-driver` addon, and the source `pvc-1` with data, kept in use by a Pod.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Clone** | A new PVC pre-filled with a **copy** of an existing PVC's data: `dataSource: {kind: PersistentVolumeClaim, name: …}`. Done by the CSI driver (`CLONE_VOLUME` capability). |
| **Rules** | CSI drivers only. **Same namespace** (dataSource has no namespace field). **Same StorageClass/driver**. **Same volumeMode**. Requested size **≥ source** size. Source must be Bound. |
| **In-use source** | Allowed. The source can be mounted by a running Pod. |
| **Independent** | After provisioning, the clone is an ordinary PVC: changes don't affect the source and vice versa. It can be cloned, snapshotted or deleted on its own. |
| **Default class** | If the default StorageClass is used, `storageClassName` can be omitted, but the class must still match the source's. |

---

## Lab 1 – Clone an in-use volume
```bash
cd concepts/storage/volume-pvc-datasource
kubectl apply -f 00-setup.yaml ; kubectl wait --for=condition=Ready pod/source-app -n myns
kubectl apply -f 01-clone-of-pvc-1.yaml
kubectl get pvc -n myns
#   clone-of-pvc-1   Bound   pvc-cc29…   5Gi   RWO   cloning
#   pvc-1            Bound   pvc-1fb1…   5Gi   RWO   cloning
kubectl apply -f 03-read-clone.yaml ; kubectl wait --for=condition=Ready pod/clone-reader -n myns
kubectl logs clone-reader -n myns                 # original-data      <- copied
kubectl exec source-app -n myns -- cat /data/file # original-data      <- the clone overwrote ITS copy; the source is unchanged
```

## Lab 2 – The rules, broken one by one
```bash
kubectl apply -f 02-bad-clones.yaml
kubectl get pvc -A | grep clone-
#   myns     clone-block          Pending
#   myns     clone-other-driver   Bound      … standard     <- !
#   myns     clone-too-small      Pending
#   otherns  clone-cross-ns       Pending
for p in myns/clone-too-small myns/clone-block otherns/clone-cross-ns; do
  kubectl get events -n ${p%/*} --field-selector involvedObject.name=${p#*/},type=Warning -o custom-columns=M:.message | tail -1; done
#   … new PVC request must be greater than or equal in size to the specified PVC data source, requested 1073741824 but source is 5368709120
#   … the source PVC and destination PVCs must have the same volume mode for cloning.  Source is Filesystem, destination is Block
#   … error getting PVC pvc-1 (namespace "otherns") from api server: persistentvolumeclaim "pvc-1" not found
```
**`clone-other-driver` is the trap.** Its class `standard` uses minikube's non-CSI `k8s.io/minikube-hostpath` provisioner, which **ignores `dataSource`**. You get a Bound, **empty** volume and no error:
```bash
kubectl run chk -n myns --image=busybox:1.36 --restart=Never --overrides='{"spec":{"volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"clone-other-driver"}}],"containers":[{"name":"chk","image":"busybox:1.36","command":["sh","-c","ls -A /data | wc -l"],"volumeMounts":[{"name":"d","mountPath":"/data"}]}]}}'
kubectl logs chk -n myns          # 0
```
A CSI provisioner asked for another driver's PVC refuses. A legacy provisioner may not even look. Always check the clone's contents.

---

## Useful commands
```bash
kubectl get pvc <clone> -o jsonpath='{.spec.dataSource}'
kubectl get events --field-selector involvedObject.name=<clone>,type=Warning
kubectl get csidriver                          # cloning needs a CSI driver
```

## Cleanup
```bash
./cleanup.sh
```
