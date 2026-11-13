# Change the Reclaim Policy of a PersistentVolume – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/change-pv-reclaim-policy/

> Runs on the default **minikube** cluster. [01-claims.yaml](01-claims.yaml) recreates the docs' sample situation: claims `default/claim1..3` (4Gi, RWO), dynamically provisioned with policy `Delete`, plus a Pod that writes a file into each. The docs' `kubectl patch` is run verbatim. [02-recover-claim.yaml](02-recover-claim.yaml) is extra: it shows what "the data can be manually recovered" looks like.

## Key ideas (read first)

| Policy | When the claim is deleted |
|---|---|
| `Delete` (default for dynamic PVs) | The PV **and the storage behind it** are deleted. |
| `Retain` | The PV goes `Released` and the data stays. An admin decides what to do: recover, clean up, delete. |
| `Recycle` | Deprecated (basic `rm -rf`, NFS/hostPath only). Use dynamic provisioning instead. |

| Topic | Meaning |
|---|---|
| **Per PV** | The policy lives on the PV (`spec.persistentVolumeReclaimPolicy`) and can be patched at any time. A StorageClass's `reclaimPolicy` only sets the value for **new** PVs. |
| **Released ≠ Available** | A Released PV still has `claimRef` to the old claim, so nothing can bind it. Remove the `claimRef` (or just its `uid`, if re-creating a claim with the same name) to reuse it. |

---

## Step 0
```bash
cd tasks/administer-cluster/change-pv-reclaim-policy
kubectl apply -f 01-claims.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/writer
```

## Lab 1 – The docs' steps
```bash
kubectl get pv
#   NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM            STORAGECLASS
#   pvc-281ea4df-e5f4-4d93-99a1-6048b58a382c   4Gi        RWO            Delete           Bound    default/claim3   standard
#   pvc-37d2a5da-2f7b-4d31-8dd8-3cbdd6291833   4Gi        RWO            Delete           Bound    default/claim2   standard
#   pvc-6bf1bce0-f190-401c-9c85-0e8d0f3ac185   4Gi        RWO            Delete           Bound    default/claim1   standard
PV3=$(kubectl get pvc claim3 -o jsonpath='{.spec.volumeName}')
kubectl patch pv $PV3 -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl get pv
#   pvc-281ea4df-...   4Gi   RWO   Retain   Bound   default/claim3   standard      <- only claim3's volume changed
#   pvc-37d2a5da-...   4Gi   RWO   Delete   Bound   default/claim2   standard
#   pvc-6bf1bce0-...   4Gi   RWO   Delete   Bound   default/claim1   standard
```

## Lab 2 – What happens when the claims go away
```bash
kubectl get pv $PV3 -o jsonpath='{.spec.hostPath.path}{"\n"}'      # /tmp/hostpath-provisioner/default/claim3
kubectl delete pod writer
kubectl delete pvc claim1 claim2 claim3
sleep 8; kubectl get pv | grep -E "NAME|claim[123]"
#   pvc-281ea4df-...   4Gi   RWO   Retain   Released   default/claim3   standard      <- the other two are gone
minikube ssh -- "sudo ls /tmp/hostpath-provisioner/default/; sudo cat /tmp/hostpath-provisioner/default/claim3/data.txt"
#   claim3                 <- claim1/claim2 directories deleted with their PVs
#   precious-data-3
```

## Lab 3 (extra) – Recover the retained volume into a new claim
```bash
sed "s/<PV_NAME>/$PV3/" 02-recover-claim.yaml | kubectl apply -f -
kubectl get pvc claim3-restored
#   claim3-restored   Pending   pvc-281ea4df-...   0            <- the PV is still reserved for the old claim
kubectl patch pv $PV3 --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/reader; kubectl logs reader
#   precious-data-3
kubectl get pv $PV3
#   pvc-281ea4df-...   4Gi   RWO   Retain   Bound   default/claim3-restored   standard
```

---

## Useful commands
```bash
kubectl get pv -o custom-columns=NAME:.metadata.name,POLICY:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase,CLAIM:.spec.claimRef.name
kubectl patch pv <pv> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```
On Windows `cmd`, use double quotes with escaped inner quotes: `kubectl patch pv <pv> -p "{\"spec\":{\"persistentVolumeReclaimPolicy\":\"Retain\"}}"`.

## Cleanup
```bash
./cleanup.sh     # policy back to Delete, then claims (and so PVs + node directories) deleted
```
