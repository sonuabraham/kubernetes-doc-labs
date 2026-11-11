# Volume Attributes Classes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/

> The docs' 4 blocks are here **verbatim**: [01-vac-silver.yaml](01-vac-silver.yaml), [03-vac-gold.yaml](03-vac-gold.yaml) and two PVC fragments containing a literal `…` ([02-…excerpt](02-pvc-silver-excerpt.yaml), [04-…excerpt](04-pvc-gold-excerpt.yaml)). [05-test-pv-claim.yaml](05-test-pv-claim.yaml) is the filled-in claim.
>
> ⚠️ **Driver side not demonstrated.** Applying the attributes needs a CSI driver with `ModifyVolume` and **new sidecars** (external-provisioner ≥ v4, external-resizer ≥ v1.10). minikube's `csi-hostpath-driver` addon ships csi-provisioner **v3.3.0** and csi-resizer **v1.6.0**. This lab shows the API behaviour and exactly how an old sidecar breaks. The modify flow is described from the docs.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **VolumeAttributesClass (VAC)** | Cluster-scoped, GA. A named set of **mutable** volume attributes (IOPS, throughput…) for one CSI `driverName`. |
| **vs StorageClass** | StorageClass: chosen once at provisioning, immutable. VAC: chosen at provisioning **and changeable later** on a bound claim. |
| **parameters** | Opaque to Kubernetes and passed to the driver. **Immutable**: make a new class instead of editing one. Max 512 entries / 256 KiB. |
| **PVC field** | `spec.volumeAttributesClassName`: one of only two spec fields mutable after binding (with `resources.requests`). |
| **Provisioner** | external-provisioner passes the VAC parameters to `CreateVolume` (`mutable_parameters`). If the named VAC doesn't exist, the claim waits. |
| **Resizer** | external-resizer watches for a changed class and calls `ControllerModifyVolume`. Progress shows in `status.modifyVolumeStatus` (`Pending` / `InProgress` / `Infeasible`). Once done, `status.currentVolumeAttributesClassName` is updated. |
| **Protection** | Finalizer `kubernetes.io/vac-protection`: a VAC referenced by any PVC/PV isn't removed until unused. |
| **Quota** | ResourceQuota can count claims per VAC (see `../../policy/resource-quotas`). |

---

## Step 1
```bash
cd concepts/storage/volume-attributes-classes
kubectl apply -f 01-vac-silver.yaml -f 03-vac-gold.yaml -f 00-setup.yaml
kubectl get vac
#   gold              csi.storage.example.com
#   hostpath-gold     hostpath.csi.k8s.io        <- same parameters, but for a driver that's installed
#   hostpath-silver   hostpath.csi.k8s.io
#   silver            csi.storage.example.com
kubectl apply -f 02-pvc-silver-excerpt.yaml --dry-run=client
#   error ... yaml: line 7: mapping values are not allowed      <- the "…" is literal; use 05-test-pv-claim.yaml
```

## Lab 1 – Parameters are immutable
```bash
kubectl patch vac silver --type=merge -p '{"parameters":{"iops":"9999"}}'
#   The VolumeAttributesClass "silver" is invalid: parameters: Forbidden: updates to parameters are forbidden.
```

## Lab 2 – Provisioning with a VAC through an OLD sidecar
```bash
kubectl apply -n vac-demo -f 05-test-pv-claim.yaml              # class silver (driver csi.storage.example.com)
kubectl get pvc test-pv-claim -n vac-demo                        # Pending, forever
kubectl get events -n vac-demo --field-selector involvedObject.name=test-pv-claim,type=Warning -o jsonpath='{.items[-1:].message}'
#   failed to provision volume with StorageClass "csi-hostpath-sc": node check failed: ...
#   PersistentVolumeClaim "test-pv-claim" is invalid: spec: Forbidden: spec is immutable after creation
#   except resources.requests and volumeAttributesClassName for bound claims
kubectl logs -n kube-system -l app.kubernetes.io/name=csi-hostpathplugin -c csi-provisioner | grep -A1 '"VolumeAttributesClassName": "silver"'
#   - "VolumeAttributesClassName": "silver"
#   + "VolumeAttributesClassName": null
```
csi-provisioner v3.3.0 was built **before** the field existed. When it updates the PVC (to claim it), it sends an object without `volumeAttributesClassName`, and the API server sees an illegal spec change. That's a general lesson: **old controllers silently drop fields they don't know.** Here even `hostpath-silver` (a matching driver) fails the same way.

## Lab 3 – Changing the class of a bound claim
```bash
kubectl create -n vac-demo -f - <<'Y'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: later-vac-claim}
spec: {storageClassName: csi-hostpath-sc, accessModes: ["ReadWriteOnce"], resources: {requests: {storage: 1Gi}}}
Y
kubectl patch pvc later-vac-claim -n vac-demo -p '{"spec":{"volumeAttributesClassName":"hostpath-gold"}}'     # allowed: bound claim
kubectl get pvc later-vac-claim -n vac-demo -o jsonpath='spec={.spec.volumeAttributesClassName} current={.status.currentVolumeAttributesClassName} modify={.status.modifyVolumeStatus}{"\n"}'
#   spec=hostpath-gold current= modify=          <- nobody acts on it: csi-resizer v1.6 has no ModifyVolume support
```
With a capable driver and resizer you'd see `modifyVolumeStatus: {status: InProgress, targetVolumeAttributesClassName: hostpath-gold}`, then `currentVolumeAttributesClassName: hostpath-gold` and an empty `modifyVolumeStatus`. That's the docs' silver → gold switch.

## Lab 4 – VAC protection
```bash
kubectl get vac hostpath-gold -o jsonpath='{.metadata.finalizers}'      # ["kubernetes.io/vac-protection"]
kubectl delete vac hostpath-gold --wait=false
kubectl get vac hostpath-gold -o jsonpath='{.metadata.deletionTimestamp}'   # set, but the object stays: later-vac-claim uses it
kubectl patch pvc later-vac-claim -n vac-demo -p '{"spec":{"volumeAttributesClassName":"does-not-exist"}}'
kubectl get vac                                                         # hostpath-gold is gone now
```
A claim may name a class that doesn't exist (yet). The modify simply waits.

---

## Useful commands
```bash
kubectl get vac
kubectl get pvc -o custom-columns=NAME:.metadata.name,VAC:.spec.volumeAttributesClassName,CURRENT:.status.currentVolumeAttributesClassName
kubectl get pvc <p> -o jsonpath='{.status.modifyVolumeStatus}'
```

## Cleanup
```bash
./cleanup.sh
```
