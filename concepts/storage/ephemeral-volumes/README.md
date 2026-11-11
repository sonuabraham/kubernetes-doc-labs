# Ephemeral Volumes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/

> The docs' two manifests are **verbatim**: [01-csi-inline-volume.yaml](01-csi-inline-volume.yaml) and [02-generic-ephemeral-volume.yaml](02-generic-ephemeral-volume.yaml). [00-setup.yaml](00-setup.yaml) creates the `scratch-storage-class` they ask for, on minikube's `csi-hostpath-driver` addon (`minikube addons enable csi-hostpath-driver`).

## Key ideas (read first)

| Type | Provided by | Notes |
|---|---|---|
| **emptyDir** | kubelet | Empty at Pod start, node disk or RAM (see `../volumes`) |
| **configMap, downwardAPI, secret** | kubelet | API data as files |
| **image** | kubelet | OCI image contents, read-only |
| **CSI ephemeral (inline)** | a CSI driver that lists `Ephemeral` in its `CSIDriver.spec.volumeLifecycleModes` | Volume spec **inside the Pod**: no PVC/PV. Parameters go in `volumeAttributes`. No scheduling awareness of capacity. Admins can restrict drivers with admission policies. |
| **Generic ephemeral** | any dynamic provisioner | `ephemeral.volumeClaimTemplate` → the **ephemeral controller** creates a PVC per Pod. Full PVC features (snapshots, clone source, resize, capacity tracking). |

| Concept | Meaning |
|---|---|
| **Lifecycle** | The generated PVC has an `ownerReference` to the Pod (`controller: true`). Delete the Pod and the GC deletes the PVC, and with the usual `Delete` reclaim policy the PV too. |
| **Naming** | PVC name = `<pod name>-<volume name>`. Names can **collide**. |
| **Safety** | The scheduler and kubelet only use a PVC the Pod **owns**. A same-named, pre-existing PVC is never taken over, and the Pod waits. |
| **Security** | Anyone who can create Pods can create PVCs indirectly this way. RBAC on PVCs doesn't stop it, so use admission policies or quotas. |

---

## Step 1
```bash
cd concepts/storage/ephemeral-volumes
kubectl apply -f 00-setup.yaml
kubectl apply -n eph-demo -f 01-csi-inline-volume.yaml -f 02-generic-ephemeral-volume.yaml -f 03-csi-inline-hostpath.yaml
kubectl get pods -n eph-demo
#   my-app                1/1  Running
#   my-csi-app            0/1  ContainerCreating
#   my-csi-app-hostpath   1/1  Running
```

## Lab 1 – CSI ephemeral (inline) volumes
```bash
kubectl get events -n eph-demo --field-selector involvedObject.name=my-csi-app,type=Warning -o custom-columns=M:.message | tail -1
#   MountVolume.SetUp failed ... driver name inline.storage.kubernetes.io not found in the list of registered CSI drivers
kubectl get csidriver -o custom-columns=NAME:.metadata.name,MODES:.spec.volumeLifecycleModes
#   hostpath.csi.k8s.io   [Persistent Ephemeral]       <- this driver supports inline use
kubectl exec my-csi-app-hostpath -n eph-demo -- sh -c 'echo hi > /data/f && mount | grep /data'
kubectl get pvc,pv -n eph-demo | grep -v scratch      # nothing for the inline volume: no PVC, no PV
```
The docs' driver name is a placeholder. [03-csi-inline-hostpath.yaml](03-csi-inline-hostpath.yaml) is the same Pod with `driver: hostpath.csi.k8s.io`. The kubelet calls the driver's `NodePublishVolume` directly at Pod start and unpublishes at Pod deletion.

## Lab 2 – Generic ephemeral volumes
```bash
kubectl get pvc -n eph-demo --show-labels
#   my-app-scratch-volume   Bound   pvc-0014…   1Gi   RWO   scratch-storage-class   type=my-frontend-volume
#   name = <pod>-<volume>; labels come from volumeClaimTemplate.metadata
kubectl get pvc my-app-scratch-volume -n eph-demo -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name} controller={.metadata.ownerReferences[0].controller}{"\n"}'
#   Pod/my-app controller=true
kubectl delete pod my-app -n eph-demo
kubectl wait --for=delete pvc/my-app-scratch-volume -n eph-demo     # gone with the Pod - and the PV (reclaim Delete) too
kubectl get pv                                                     # No resources found
```

## Lab 3 – Name collisions and the ownership check
```bash
kubectl apply -n eph-demo -f 04-name-collision.yaml       # pod-a + volume scratch   vs   pod + volume a-scratch
kubectl get pods -n eph-demo pod pod-a                    # pod-a Running, pod Pending
kubectl get events -n eph-demo --field-selector involvedObject.name=pod,type=Warning -o custom-columns=M:.message | tail -1
#   0/1 nodes are available: PVC eph-demo/pod-a-scratch was not created for pod eph-demo/pod (pod is not owner).
```
The same check stops a Pod from adopting a PVC someone created by hand:
```bash
kubectl delete pod pod pod-a -n eph-demo
kubectl create -n eph-demo -f - <<'Y'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: my-app-scratch-volume}
spec: {accessModes: ["ReadWriteOnce"], storageClassName: scratch-storage-class, resources: {requests: {storage: 1Gi}}}
Y
kubectl apply -n eph-demo -f 02-generic-ephemeral-volume.yaml
#   my-app stays Pending: "PVC eph-demo/my-app-scratch-volume was not created for pod eph-demo/my-app (pod is not owner)"
```

---

## Useful commands
```bash
kubectl get csidriver -o custom-columns=NAME:.metadata.name,MODES:.spec.volumeLifecycleModes
kubectl get pvc -o custom-columns=NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].name
kubectl explain pod.spec.volumes.ephemeral.volumeClaimTemplate
```

## Cleanup
```bash
./cleanup.sh
```
