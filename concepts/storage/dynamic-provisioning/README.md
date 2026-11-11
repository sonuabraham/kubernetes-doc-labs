# Dynamic Volume Provisioning – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/

> The docs' 3 blocks are **verbatim**: [01-storageclass-slow.yaml](01-storageclass-slow.yaml), [02-storageclass-fast.yaml](02-storageclass-fast.yaml) (both `kubernetes.io/gce-pd`) and [03-claim1.yaml](03-claim1.yaml). They need Google Cloud, so [00-setup.yaml](00-setup.yaml) adds equivalents on minikube's `csi-hostpath-driver` addon (`minikube addons enable csi-hostpath-driver`).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Dynamic provisioning** | Volumes created **on demand** when a claim asks, so there's no admin pre-creating PVs. |
| **StorageClass** | The admin's menu: `provisioner` + `parameters`. Several classes for one provisioner (`slow` = pd-standard, `fast` = pd-ssd). |
| **Using it** | The PVC sets `storageClassName`. The provisioner creates a PV of at least the requested size and binds it. Reclaim is `Delete` by default, so deleting the claim deletes the volume. |
| **Defaulting** | Mark one class default (`storageclass.kubernetes.io/is-default-class`, DefaultStorageClass admission plugin) → claims without a class use it. See `../storage-classes`. |
| **Topology awareness** | Multi-zone clusters: with `WaitForFirstConsumer`, the volume is provisioned in the zone/node where the Pod gets scheduled. |
| **In-tree → CSI** | `kubernetes.io/gce-pd` and friends are legacy names. **CSI migration** redirects them to the CSI driver (`pd.csi.storage.gke.io`). |

---

## Step 1
```bash
cd concepts/storage/dynamic-provisioning
kubectl apply -f 00-setup.yaml -f 01-storageclass-slow.yaml -f 02-storageclass-fast.yaml
```

## Lab 1 – The docs' claim on a non-GCE cluster
```bash
kubectl apply -n dp-demo -f 03-claim1.yaml
kubectl get pvc claim1 -n dp-demo                  # Pending   fast
kubectl get events -n dp-demo --field-selector involvedObject.name=claim1 -o custom-columns=M:.message
#   Waiting for a volume to be created either by the external provisioner 'pd.csi.storage.gke.io' ...
kubectl get pvc claim1 -n dp-demo -o jsonpath='{.metadata.annotations.volume\.kubernetes\.io/storage-provisioner}'
#   pd.csi.storage.gke.io             <- class says kubernetes.io/gce-pd; CSI migration translated it
```
The class and claim are valid API objects. Nothing provisions because the GCE PD CSI driver isn't installed.

## Lab 2 – The same flow, working
```bash
kubectl apply -n dp-demo -f 04-claim-fast-hostpath.yaml       # claim1 shape (30Gi) on class slow-hostpath
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/claim1-hostpath -n dp-demo
PV=$(kubectl get pvc claim1-hostpath -n dp-demo -o jsonpath='{.spec.volumeName}')
kubectl get pv $PV -o jsonpath='name={.metadata.name} cap={.spec.capacity.storage} reclaim={.spec.persistentVolumeReclaimPolicy} provisioned-by={.metadata.annotations.pv\.kubernetes\.io/provisioned-by}{"\n"}'
#   name=pvc-4f672d11-… cap=30Gi reclaim=Delete provisioned-by=hostpath.csi.k8s.io   <- PV named pvc-<claim UID>
kubectl delete pvc claim1-hostpath -n dp-demo
kubectl wait --for=delete pv/$PV                               # the PV (and backing storage) goes with the claim
```

## Lab 3 – Topology awareness (WaitForFirstConsumer)
```bash
kubectl create -n dp-demo -f - <<'Y'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: topo-claim}
spec: {storageClassName: fast-hostpath, accessModes: ["ReadWriteOnce"], resources: {requests: {storage: 1Gi}}}
---
apiVersion: v1
kind: Pod
metadata: {name: topo-pod}
spec:
  containers: [{name: c, image: busybox:1.36, command: ["sleep","3600"], volumeMounts: [{name: v, mountPath: /v}]}]
  volumes: [{name: v, persistentVolumeClaim: {claimName: topo-claim}}]
Y
kubectl get pvc topo-claim -n dp-demo -o jsonpath='{.metadata.annotations.volume\.kubernetes\.io/selected-node}{"\n"}'     # minikube
kubectl get pv $(kubectl get pvc topo-claim -n dp-demo -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.nodeAffinity.required}{"\n"}'
#   {"nodeSelectorTerms":[{"matchExpressions":[{"key":"topology.hostpath.csi/node","operator":"In","values":["minikube"]}]}]}
```
The scheduler picked the node first, and the driver created the volume **there** and stamped that topology onto the PV. On a cloud cluster the key is the zone.

---

## Useful commands
```bash
kubectl get sc ; kubectl get pvc,pv
kubectl get events --field-selector involvedObject.name=<pvc>
kubectl get pv <pv> -o jsonpath='{.metadata.annotations.pv\.kubernetes\.io/provisioned-by}'
```

## Cleanup
```bash
./cleanup.sh
```
