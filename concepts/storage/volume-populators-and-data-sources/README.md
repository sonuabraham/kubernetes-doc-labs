# Volume Populators and Data Sources – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/volume-populators-and-data-sources/

> The docs' 3 blocks are **verbatim**: [01-populated-pvc.yaml](01-populated-pvc.yaml), [02-referencegrant.yaml](02-referencegrant.yaml) and [03-cross-namespace-pvc.yaml](03-cross-namespace-pvc.yaml) (indented as in the docs' list, still valid YAML). [00-setup.yaml](00-setup.yaml) defines the custom kind `ExampleDataSource` and creates `example-name`. [toy-populator.sh](toy-populator.sh) is a minimal populator for that kind.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **dataSource** (old) | Only `PersistentVolumeClaim` (clone) or `VolumeSnapshot` (restore). Anything else is **silently dropped**. |
| **dataSourceRef** (new) | **Any** object: core kinds or a custom resource (`apiGroup` + `kind` + `name`). Invalid values are **errors**, not silently ignored. |
| **Mirroring** | Set one and the API server copies it to the other when possible (core kinds). Set both and they must match. Custom kinds live only in `dataSourceRef`. |
| **Volume populator** | A controller that watches PVCs whose `dataSourceRef` is **its** kind and fills a new volume from it (an image, a backup, a URL…). Out-of-tree: install it like any controller. |
| **Provisioner contract** | A compliant CSI provisioner leaves such claims alone ("Assuming an external populator will provision the volume"). |
| **volume-data-source-validator** | Optional controller + `VolumePopulator` CRD: registers kinds and raises events for claims whose kind has no populator. |
| **Cross-namespace** (alpha) | `dataSourceRef.namespace`, allowed by a Gateway API **ReferenceGrant** in the source namespace. Needs gates `AnyVolumeDataSource` + `CrossNamespaceVolumeDataSource` (apiserver, controller-manager, csi-provisioner). |

---

## Step 1
```bash
cd concepts/storage/volume-populators-and-data-sources
kubectl apply -f 00-setup.yaml        # run twice the first time: the CR needs the CRD to be Established
```
CRDs in a `*.k8s.io` group (like the docs' `example.storage.k8s.io`) are refused without an annotation:
`metadata.annotations[api-approved.kubernetes.io]: Required value: protected groups must have approval annotation`. Ours says `"unapproved, toy example for a lab"`.

## Lab 1 – Who acts on a dataSourceRef?
```bash
kubectl apply -n pop-demo -f 01-populated-pvc.yaml          # docs: no class → default "standard" (legacy minikube-hostpath)
kubectl apply -n pop-demo -f 04-populated-pvc-csi.yaml      # same + storageClassName: csi-hostpath-sc
kubectl get pvc -n pop-demo
#   populated-pvc       Bound     pvc-8f6b…   standard           <- legacy provisioner ignored the data source: EMPTY volume
#   populated-pvc-csi   Pending               csi-hostpath-sc    <- CSI provisioner steps aside:
kubectl get events -n pop-demo --field-selector involvedObject.name=populated-pvc-csi -o custom-columns=M:.message
#   Assuming an external populator will provision the volume
```

## Lab 2 – Run a populator
```bash
./toy-populator.sh                  # terminal 2
#   10:32:43 populated pop-demo/populated-pvc-csi from ExampleDataSource example-name (README.txt, seed.csv) -> PV populated-38d4…
kubectl get pvc populated-pvc-csi -n pop-demo        # Bound   populated-38d4…   10Gi
kubectl run reader -n pop-demo --image=busybox:1.36 --restart=Never --overrides='{"spec":{"volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"populated-pvc-csi"}}],"containers":[{"name":"reader","image":"busybox:1.36","command":["sh","-c","ls /data; cat /data/seed.csv"],"volumeMounts":[{"name":"d","mountPath":"/data"}]}]}}'
kubectl logs reader -n pop-demo
#   README.txt  seed.csv
#   id,name / 1,alice / 2,bob          <- the volume arrived with content
```
Real populators (on `lib-volume-populator`) fill a hidden "prime" PVC with a worker Pod, then hand its PV to your claim. The toy writes a node directory and pre-binds a PV via `claimRef`. The contract the user sees is the same: **claim Pending → claim Bound with data**.

## Lab 3 – dataSource vs dataSourceRef
```bash
# custom kind in dataSource
kubectl create -n pop-demo --dry-run=server -o jsonpath='ds={.spec.dataSource} dsr={.spec.dataSourceRef}' -f - <<'Y'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: ds-custom}
spec: {accessModes: ["ReadWriteOnce"], resources: {requests: {storage: 1Gi}}, dataSource: {kind: ExampleDataSource, apiGroup: example.storage.k8s.io, name: example-name}}
Y
#   ds= dsr=                       <- silently DROPPED (same for e.g. kind: ConfigMap)
```
| Input | Stored |
|---|---|
| `dataSource: {kind: PersistentVolumeClaim, name: x}` | both fields `{kind: PersistentVolumeClaim, name: x}` (mirrored) |
| `dataSource: {kind: ExampleDataSource …}` or `{kind: ConfigMap}` | both empty (dropped) |
| `dataSource: …a` + `dataSourceRef: …b` | **rejected**: `must match dataSourceRef` |

## Lab 4 – Cross-namespace data sources (alpha, off)
```bash
kubectl apply -f 02-referencegrant.yaml
#   no matches for kind "ReferenceGrant" in version "gateway.networking.k8s.io/v1beta1"   <- Gateway API CRDs not installed
kubectl create namespace ns1 ; kubectl apply -f 03-cross-namespace-pvc.yaml
kubectl get pvc foo-pvc -n ns1 -o jsonpath='ds={.spec.dataSource} dsr={.spec.dataSourceRef}{"\n"}'
#   ds= dsr=                       <- CrossNamespaceVolumeDataSource is off: a dataSourceRef with a namespace is dropped
```
With the gates on, ReferenceGrant installed (see `../../services-networking/gateway-api`) and a cross-namespace-aware csi-provisioner, `ns1/foo-pvc` would be restored from `default/new-snapshot-demo`.

---

## Useful commands
```bash
kubectl get pvc <p> -o jsonpath='{.spec.dataSource}{"\n"}{.spec.dataSourceRef}{"\n"}'
kubectl get events --field-selector involvedObject.name=<p>
kubectl get --raw /metrics | grep -E 'feature_enabled.*(AnyVolumeDataSource|CrossNamespaceVolumeDataSource)'
```

## Cleanup
```bash
./cleanup.sh       # namespaces, toy PVs, CRD, node dir. Stop toy-populator.sh with Ctrl-C.
```
