# Limit Storage Consumption – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/limit-storage-consumption/

> Runs on the default **minikube** cluster in namespace `storage-demo`. The docs' YAML is copied **verbatim**: [01-storagelimits.yaml](01-storagelimits.yaml) (LimitRange) and [02-storagequota.yaml](02-storagequota.yaml) (ResourceQuota). [03-pvc.yaml](03-pvc.yaml) is a PVC template (not from the docs) used to test the page's three claims: a 10Gi PVC is rejected, a 3rd 2Gi PVC breaks the 5Gi total, and a 6th PVC breaks the count.

## Key ideas (read first)

| Object | Limits |
|---|---|
| **LimitRange** `type: PersistentVolumeClaim` | Each claim's `requests.storage` between `min` (1Gi) and `max` (2Gi). Useful when a backend has a minimum size (e.g. EBS 1Gi). |
| **ResourceQuota** `persistentvolumeclaims` | Number of PVCs in the namespace (5). |
| **ResourceQuota** `requests.storage` | Sum of all PVC requests in the namespace (5Gi). |
| **Per class** | `<class>.storageclass.storage.k8s.io/requests.storage` and `.../persistentvolumeclaims` cap usage per StorageClass. |

All checks happen at **admission**: rejected PVCs are never created.

---

## Step 0
```bash
cd tasks/administer-cluster/limit-storage-consumption
kubectl create ns storage-demo
kubectl apply -n storage-demo -f 01-storagelimits.yaml -f 02-storagequota.yaml
p(){ sed -e s/NAME/$1/ -e s/SIZE/$2/ 03-pvc.yaml | kubectl apply -n storage-demo -f -; }
```

## Lab 1 – LimitRange: size per claim
```bash
p too-big 10Gi
#   persistentvolumeclaims "too-big" is forbidden: maximum storage usage per PersistentVolumeClaim is 2Gi, but request is 10Gi
p too-small 500Mi
#   persistentvolumeclaims "too-small" is forbidden: minimum storage usage per PersistentVolumeClaim is 1Gi, but request is 500Mi
```

## Lab 2 – ResourceQuota: total capacity ("3 PVCs of 2Gi = 6Gi > 5Gi")
```bash
p pvc-a 2Gi; p pvc-b 2Gi           # created, created
p pvc-c 2Gi
#   persistentvolumeclaims "pvc-c" is forbidden: exceeded quota: storagequota, requested: requests.storage=2Gi,
#   used: requests.storage=4Gi, limited: requests.storage=5Gi
p pvc-c 1Gi                        # created (5Gi exactly)
kubectl describe quota storagequota -n storage-demo
#   persistentvolumeclaims  3     5
#   requests.storage        5Gi   5Gi
```

## Lab 3 – ResourceQuota: claim count ("a 6th PVC would be rejected")
Raise the capacity cap so that only the count matters:
```bash
kubectl delete ns storage-demo; kubectl create ns storage-demo
kubectl apply -n storage-demo -f 01-storagelimits.yaml -f 02-storagequota.yaml
kubectl -n storage-demo patch quota storagequota -p '{"spec":{"hard":{"requests.storage":"10Gi"}}}'
for i in 1 2 3 4 5 6; do p pvc-$i 1Gi; done
#   pvc-1 ... pvc-5 created
#   persistentvolumeclaims "pvc-6" is forbidden: exceeded quota: storagequota, requested: persistentvolumeclaims=1,
#   used: persistentvolumeclaims=5, limited: persistentvolumeclaims=5
```
A PVC with no size at all isn't defaulted by this LimitRange (it has no `default`): `spec.resources[storage]: Required value`.

---

## Useful commands
```bash
kubectl describe limitrange storagelimits -n storage-demo
kubectl describe quota storagequota -n storage-demo
```

## Cleanup
```bash
kubectl delete ns storage-demo
```
