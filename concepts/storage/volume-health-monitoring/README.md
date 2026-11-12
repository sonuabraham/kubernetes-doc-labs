# Volume Health Monitoring – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/volume-health-monitoring/

> The page's 3 blocks are **status excerpts** (`# ...`), kept verbatim: [01-pod-volumehealth-excerpt.yaml](01-pod-volumehealth-excerpt.yaml), [02-csinode-storagehealth-excerpt.yaml](02-csinode-storagehealth-excerpt.yaml), [03-pvc-healthstatus-excerpt.yaml](03-pvc-healthstatus-excerpt.yaml). The lab writes them into real objects.
>
> ⚠️ **No driver reports health here.** The new mechanism needs CSI drivers that implement the new RPCs, and the addon's hostpath driver (v1.9) and health-monitor sidecar (v0.7) predate them. This lab shows the **API side**: the gate, the fields, validation, and who owns what.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Goal** | Drivers report volume and backend problems as **durable status fields** that automation can watch, instead of Events or vendor dashboards. |
| **Gate** | `CSIVolumeHealth` (alpha, **off** in v1.37) on kube-apiserver (fields stored) and kubelet (node probing). A redesign: the old alpha Events + `kubelet_volume_stats_health_status_abnormal` metric are gone. |
| **Pod `.status.volumeHealth`** | Written by the **kubelet** from `NodeGetVolumeHealth`, per `spec.volumes` name, every `volumeStatsAggPeriod`. |
| **CSINode `.status.storageHealth`** | Written by the kubelet from `NodeGetStorageHealth`, per driver. Optional `accessMode` / `volumeMode` scope. Metric `csi_node_storage_health_status`. |
| **PVC `.status.healthStatus`** | Written **only** by `csi-external-health-monitor-controller` (control plane) from `ControllerListVolumeHealth` / `ControllerGetVolumeHealth`. Nodes can't touch it. |
| **Values** | Volume: `Inaccessible`, `DataLoss`, `Degraded`. Backend: `StorageUnreachable`, `StorageDegraded`. Plus driver-defined `reason` and `message`. |
| **Report only** | Kubernetes never acts on these: no rescheduling or failover. Remediation is up to you or your vendor. |

---

## Lab 1 – Gate off (main `minikube` profile)
```bash
cd concepts/storage/volume-health-monitoring
kubectl get --raw /metrics | grep 'name="CSIVolumeHealth"'
#   kubernetes_feature_enabled{name="CSIVolumeHealth",stage="ALPHA"} 0
kubectl apply -f 00-setup.yaml ; kubectl wait --for=condition=Ready pod/my-pod -n health-demo
kubectl patch pvc my-claim -n health-demo --subresource=status --type=merge \
  -p '{"status":{"healthStatus":{"healthConditions":[{"status":"Inaccessible","reason":"VolumeNotFound","message":"volume not found on the storage backend"}]}}}' \
  -o jsonpath='[{.status.healthStatus}]{"\n"}'
#   []          <- patch "succeeds", field silently DROPPED by the apiserver
```

## Lab 2 – Gate on: the fields exist
```bash
./start-vh-lab.sh          # profile vh-lab, --feature-gates=CSIVolumeHealth=true (switches kubectl context)
kubectl create ns health-demo
# claim + pod as in 00-setup.yaml but with the default class (no CSI driver in this profile):
sed -e 's/  storageClassName: csi-hostpath-sc\n//' 00-setup.yaml | grep -v csi-hostpath-sc | kubectl apply -f -
J(){ python3 -c "import yaml,json;print(json.dumps(yaml.safe_load(open('$1'))['status']))"; }
kubectl patch pvc my-claim -n health-demo --subresource=status --type=merge -p "{\"status\":$(J 03-pvc-healthstatus-excerpt.yaml)}" -o jsonpath='{.status.healthStatus}{"\n"}'
#   {"healthConditions":[{"message":"volume not found on the storage backend","reason":"VolumeNotFound","status":"Inaccessible"}],"lastTransitionTime":"2026-07-20T12:00:00Z"}
kubectl patch pod my-pod -n health-demo --subresource=status --type=merge -p "{\"status\":$(J 01-pod-volumehealth-excerpt.yaml)}" -o jsonpath='{.status.volumeHealth}{"\n"}'
#   [{"healthConditions":[...Inaccessible...],"name":"my-volume"}]
kubectl patch csinode vh-lab --subresource=status --type=merge -p "{\"status\":$(J 02-csinode-storagehealth-excerpt.yaml)}" -o jsonpath='{.status}{"\n"}'
#   {"storageHealth":[{"healthConditions":[{"message":"data path ... unreachable from this node","reason":"NetworkPartition","status":"StorageUnreachable"}],"name":"csi.example.com"}]}
```
Values are validated:
```bash
kubectl patch pvc my-claim -n health-demo --subresource=status --type=merge -p '{"status":{"healthStatus":{"healthConditions":[{"status":"OnFire","reason":"x"}]}}}'
#   status.healthStatus.healthConditions[0].status: Unsupported value: "OnFire": supported values: "DataLoss", "Degraded", "Inaccessible"
```

## Lab 3 – Who owns which field
```bash
sleep 70
kubectl get pod my-pod -n health-demo -o jsonpath='[{.status.volumeHealth}]{"\n"}'
#   []          <- the KUBELET owns pod volumeHealth: its next probe cycle rewrote it (no CSI volume → nothing to report)
kubectl get csinode vh-lab -o jsonpath='{.status.storageHealth[0].name}{"\n"}'
#   csi.example.com   <- untouched: no such driver registered, so the kubelet has nothing to replace it with
```
The PVC field stays as written because only the controller-side sidecar writes it, and none runs here. In a real cluster, the kubelet is authorized (Node authorizer + NodeRestriction) to update only its **own** CSINode status, and no node can write PVC health.

```bash
minikube stop -p vh-lab ; kubectl config use-context minikube
```

## What you'd see with a supporting driver
- `kubectl get pvc -o custom-columns=NAME:.metadata.name,HEALTH:.status.healthStatus.healthConditions[*].status` populated by the sidecar.
- Pods with an `Inaccessible` volume stay Running. Your controller decides whether to delete or move them.
- On the kubelet's `/metrics`: `csi_node_storage_health_status{driver_name="…",status="StorageUnreachable",reason="…"} 1`.

---

## Useful commands
```bash
kubectl get pvc -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,HEALTH:.status.healthStatus.healthConditions[*].status
kubectl get pod <p> -o jsonpath='{.status.volumeHealth}'
kubectl get csinode -o jsonpath='{range .items[*]}{.metadata.name}: {.status.storageHealth}{"\n"}{end}'
```

## Cleanup
```bash
./cleanup.sh       # health-demo on minikube; stops vh-lab and switches back to the minikube context
```
