# Change the Access Mode of a PersistentVolume to ReadWriteOncePod – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/change-pv-access-mode-readwriteoncepod/

> Runs on the default **minikube** cluster with the **csi-hostpath** addon (enabled in the concepts storage labs). Its sidecars meet the page's minimums: provisioner v3.3.0 ≥ 3.0.0, attacher v4.0.0 ≥ 3.3.0, resizer v1.6.0 ≥ 1.3.0. Files:
> - Docs YAML, **verbatim**: [cat-pictures-pvc.yaml](cat-pictures-pvc.yaml) and [cat-pictures-writer-deployment.yaml](cat-pictures-writer-deployment.yaml).
> - The docs' PVC has no `storageClassName`, so on minikube it would go to the non-CSI `standard` class, and RWOP is **CSI-only**. [cat-pictures-pvc-csi.yaml](cat-pictures-pvc-csi.yaml) is the same claim on `csi-hostpath-sc`.
> - [cat-pictures-pvc-rwop.yaml](cat-pictures-pvc-rwop.yaml) is the PVC after the page's "edit before applying" step.
> - Everything runs in namespace `rwop-demo`, set as the context's namespace so the docs' commands work unchanged. [cleanup.sh](cleanup.sh) resets it.

## Key ideas (read first)

| Mode | Who may use the volume |
|---|---|
| `ReadWriteOnce` (RWO) | read-write by **one node**, but any number of Pods **on that node** |
| `ReadWriteOncePod` (RWOP, GA 1.29) | read-write by **exactly one Pod** in the whole cluster. The scheduler refuses a second Pod. |

| Migration step | Why |
|---|---|
| PV reclaim policy → `Retain` | Deleting the PVC must not delete the data. |
| Stop the workload, delete the PVC | You can't change a bound claim's access modes. |
| Clear `claimRef.uid` | The PV goes `Released` → `Available` but stays **reserved** for the same claim name/namespace. |
| PV `accessModes: [ReadWriteOncePod]` | RWOP can't be combined with other modes. |
| New PVC: RWOP + `volumeName` | Binds back to exactly this PV. |
| Reclaim policy back to `Delete` | Optional; restores the original lifecycle. |

---

## Step 0 – the "before" state: an RWO volume shared by 3 Pods
```bash
cd tasks/administer-cluster/change-pv-access-mode-readwriteoncepod
kubectl create ns rwop-demo && kubectl config set-context --current --namespace=rwop-demo
kubectl apply -f cat-pictures-pvc-csi.yaml
kubectl apply -f cat-pictures-writer-deployment.yaml
kubectl rollout status deploy cat-pictures-writer
kubectl get pvc,po
#   persistentvolumeclaim/cat-pictures-pvc   Bound   pvc-55edf852-...   1Gi   RWO
#   pod/cat-pictures-writer-...-dl9hv   1/1   Running     (x3 - all on the one node, all mounting the volume)
PV=$(kubectl get pvc cat-pictures-pvc -o jsonpath='{.spec.volumeName}'); echo $PV      # dynamic: not "cat-pictures-pv"
kubectl get pv $PV -o jsonpath='{.spec.accessModes} {.spec.persistentVolumeReclaimPolicy} {.spec.csi.driver}{"\n"}'
#   ["ReadWriteOnce"] Delete hostpath.csi.k8s.io
P1=$(kubectl get po -l app=cat-pictures-writer -o name | head -1); P2=$(kubectl get po -l app=cat-pictures-writer -o name | tail -1)
kubectl exec $P1 -- sh -c 'echo meow > /mnt/cat.txt'; kubectl exec $P2 -- cat /mnt/cat.txt
#   meow        <- two writers on the same RWO volume: exactly what RWOP prevents
```

## Lab 1 – Protect the data, release the claim
```bash
kubectl patch pv $PV -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl scale --replicas=0 deployment cat-pictures-writer
kubectl delete pvc cat-pictures-pvc
kubectl get pv $PV -o jsonpath='{.status.phase} claimRef.uid={.spec.claimRef.uid}{"\n"}'
#   Released claimRef.uid=55edf852-...          <- still points at the deleted claim's UID
kubectl patch pv $PV -p '{"spec":{"claimRef":{"uid":""}}}'
kubectl get pv $PV -o jsonpath='{.status.phase} claimRef={.spec.claimRef}{"\n"}'
#   Available claimRef={"kind":"PersistentVolumeClaim","name":"cat-pictures-pvc","namespace":"rwop-demo",...}   <- reserved for that name
```

## Lab 2 – Switch the PV to ReadWriteOncePod
```bash
kubectl patch pv $PV -p '{"spec":{"accessModes":["ReadWriteOnce","ReadWriteOncePod"]}}'
#   The PersistentVolume "pvc-..." is invalid: spec.accessModes: Forbidden: may not use ReadWriteOncePod with other access modes
kubectl patch pv $PV -p '{"spec":{"accessModes":["ReadWriteOncePod"]}}'
```

## Lab 3 – Recreate the PVC (RWOP + volumeName) and the workload
```bash
sed "s/<PV_NAME>/$PV/" cat-pictures-pvc-rwop.yaml | kubectl apply -f -
kubectl apply -f cat-pictures-writer-deployment.yaml          # back to replicas: 3
kubectl get pvc
#   cat-pictures-pvc   Bound   pvc-55edf852-...   1Gi   RWOP   csi-hostpath-sc
kubectl get po
#   cat-pictures-writer-...-rtdrz   1/1   Running
#   cat-pictures-writer-...-fcbhx   0/1   Pending
#   cat-pictures-writer-...-ggh8z   0/1   Pending
kubectl describe po <a-pending-pod> | tail -1
#   FailedScheduling  0/1 nodes are available: 1 node(s) unavailable due to PersistentVolumeClaim with
#                     ReadWriteOncePod access mode already in-use by another pod.
kubectl exec deploy/cat-pictures-writer -- cat /mnt/cat.txt           # meow - same data
kubectl patch pv $PV -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}'
```
A 3-replica Deployment doesn't make sense on an RWOP volume. Use `replicas: 1` with `strategy: Recreate` (a RollingUpdate's surge Pod would wait forever), or a StatefulSet with a claim per replica.

---

## Useful commands
```bash
kubectl get pv,pvc -o custom-columns=NAME:.metadata.name,MODES:.spec.accessModes,PHASE:.status.phase
kubectl get pv <pv> -o jsonpath='{.spec.claimRef}'
```

## Cleanup
```bash
./cleanup.sh       # namespace (PVC, and the PV via Delete) + context namespace back to default
```
