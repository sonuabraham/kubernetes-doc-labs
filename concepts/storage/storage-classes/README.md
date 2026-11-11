# Storage Classes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/storage-classes/

> All 10 docs manifests are here **verbatim** (`storageclass-*.yaml`, `pod-volume-binding.yaml`). Most name cloud or vendor provisioners, so they're applied with `--dry-run=server`. The behaviour is shown with classes on minikube's `csi-hostpath-driver` addon (`minikube addons enable csi-hostpath-driver`), created by [00-setup.yaml](00-setup.yaml).

## Key ideas (read first)

| Field | Meaning |
|---|---|
| **StorageClass** | Cluster-scoped "profile" for dynamic provisioning. Name + `provisioner` + `parameters` are **immutable** once created. |
| **provisioner** | Who creates volumes: a CSI driver name, a legacy in-tree `kubernetes.io/…` (deprecated, migrated to CSI), an external one, or `kubernetes.io/no-provisioner` (local PVs, created by hand). |
| **parameters** | Opaque, driver-specific (`type: io1`, `fileSystemId`…). Max 512 entries / 256 KiB. `csi.storage.k8s.io/*` keys are read by the CSI sidecars. |
| **reclaimPolicy** | `Delete` (default) or `Retain`. Copied into each provisioned PV. |
| **allowVolumeExpansion** | Lets claims grow (see `../persistent-volumes`, Lab 5). |
| **mountOptions** | Copied to the PV and used at mount. Not validated: a bad option fails at **mount** time. |
| **volumeBindingMode** | `Immediate`: provision/bind at PVC creation (may pick a place the Pod can't run). `WaitForFirstConsumer`: wait for a scheduled Pod, then provision where it runs. |
| **allowedTopologies** | Restrict where volumes may be provisioned (zones, nodes). |
| **Default class** | Annotation `storageclass.kubernetes.io/is-default-class: "true"`. Claims **without** `storageClassName` get it, also **retroactively** when a default appears later. `""` means "no class, ever". If several are default, the **newest** wins. |

---

## Step 1 – The docs classes
```bash
cd concepts/storage/storage-classes
for f in storageclass-*.yaml; do kubectl apply -f $f --dry-run=server; done
#   storageclass.storage.k8s.io/ebs-sc created (server dry run)        … all accepted, except:
#   The StorageClass "standard" is invalid: provisioner: … field is immutable; parameters: … field is immutable; volumeBindingMode: … field is immutable
```
`storageclass-topology.yaml` is named `standard`, the same as minikube's default class, so applying it is an **update** of immutable fields. Pick unique class names.
```bash
kubectl apply -f 00-setup.yaml
kubectl get sc
#   csi-default (default)   hostpath.csi.k8s.io        Delete  Immediate
#   csi-hostpath-sc         hostpath.csi.k8s.io        Delete  Immediate
#   csi-wffc-retain         hostpath.csi.k8s.io        Retain  WaitForFirstConsumer
#   standard                k8s.io/minikube-hostpath   Delete  Immediate     <- still annotated default too
```

## Lab 1 – Default class: unset vs "" vs two defaults
```bash
kubectl apply -n sc-demo -f 01-pvc-noclass.yaml
kubectl get pvc -n sc-demo -o custom-columns=NAME:.metadata.name,CLASS:.spec.storageClassName,STATUS:.status.phase
#   pvc-empty                 Pending       <- "" = no class: only a classless PV could match
#   pvc-unset   csi-default   Pending/Bound <- two defaults → the NEWEST (csi-default) was chosen
```

## Lab 2 – Retroactive default assignment
```bash
kubectl delete pvc --all -n sc-demo
kubectl annotate sc standard csi-default storageclass.kubernetes.io/is-default-class=false --overwrite
kubectl apply -n sc-demo -f 01-pvc-noclass.yaml
#   pvc-unset   <none>   Pending         <- no default exists: class stays unset
kubectl annotate sc csi-default storageclass.kubernetes.io/is-default-class=true --overwrite
kubectl get pvc -n sc-demo -o custom-columns=NAME:.metadata.name,CLASS:.spec.storageClassName,STATUS:.status.phase
#   pvc-empty                 Pending       <- "" is never touched
#   pvc-unset   csi-default   Bound         <- filled in AFTER the fact
kubectl annotate sc standard storageclass.kubernetes.io/is-default-class=true --overwrite      # restore
kubectl annotate sc csi-default storageclass.kubernetes.io/is-default-class=false --overwrite
```

## Lab 3 – WaitForFirstConsumer (docs `pod-volume-binding.yaml`)
```bash
kubectl apply -n sc-demo -f 02-task-pv-claim.yaml
kubectl get events -n sc-demo --field-selector involvedObject.name=task-pv-claim -o custom-columns=R:.reason,M:.message
#   WaitForFirstConsumer   waiting for first consumer to be created before binding
kubectl apply -n sc-demo -f pod-volume-binding.yaml          # nodeSelector kubernetes.io/hostname: kube-01
#   Pending: 0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector   - claim still unbound
kubectl delete pod task-pv-pod -n sc-demo
sed 's/kube-01/minikube/' pod-volume-binding.yaml | kubectl apply -n sc-demo -f -
kubectl get pvc task-pv-claim -n sc-demo -o jsonpath='{.status.phase} selected-node={.metadata.annotations.volume\.kubernetes\.io/selected-node}{"\n"}'
#   Bound selected-node=minikube        <- the scheduler picked the node, THEN the volume was provisioned there
kubectl get pv $(kubectl get pvc task-pv-claim -n sc-demo -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.mountOptions} {.spec.persistentVolumeReclaimPolicy}{"\n"}'
#   ["noatime"] Retain                  <- copied from the class
```
The docs' warning about `nodeName`:
```bash
kubectl apply -n sc-demo -f 03-nodename-pod.yaml
#   nodename-pod  ContainerCreating forever; nodename-claim  Pending
#   "error processing PVC sc-demo/nodename-claim: PVC is not bound"   <- no scheduler, no selected-node, no provisioning
```
Use `nodeSelector` / node affinity with `kubernetes.io/hostname` instead (as the docs' Pod does).

## Lab 4 – reclaimPolicy: Retain
```bash
kubectl delete pod task-pv-pod -n sc-demo ; kubectl delete pvc task-pv-claim -n sc-demo
kubectl get pv | grep csi-wffc-retain
#   pvc-7b4a…   1Gi   RWO   Retain   Released   sc-demo/task-pv-claim   csi-wffc-retain     <- volume and data kept
```

## Lab 5 – allowedTopologies
```bash
kubectl get node minikube --show-labels | tr , '\n' | grep topology     # topology.hostpath.csi/node=minikube  (published by the CSI driver)
kubectl apply -f 04-allowed-topologies.yaml                               # class only allows node "node-x"
kubectl get events -n sc-demo --field-selector involvedObject.name=topo-pod,type=Warning -o custom-columns=M:.message | tail -1
#   0/1 nodes are available: 1 node(s) didn't find available persistent volumes to bind.
kubectl patch sc csi-only-node-x --type=merge -p '{"allowedTopologies":[{"matchLabelExpressions":[{"key":"topology.hostpath.csi/node","values":["minikube"]}]}]}'
kubectl get pod topo-pod -n sc-demo        # Running   (allowedTopologies, unlike parameters, is mutable)
```
The docs' `storageclass-topology.yaml` and `storageclass-aws-ebs.yaml` do the same with `topology.kubernetes.io/zone` / `topology.ebs.csi.aws.com/zone`.

## Lab 6 – Local (no provisioner)
```bash
kubectl apply -f storageclass-local.yaml
minikube ssh -- "sudo mkdir -p /mnt/disks/vol1"
kubectl apply -f 05-local-pv.yaml          # PV by hand (nodeAffinity → minikube) + claim + Pod
kubectl get pvc local-claim -n sc-demo     # Bound local-pv-1 2Gi   - bound only once local-pod was scheduled
```
`kubernetes.io/no-provisioner` + `WaitForFirstConsumer` is the standard combination for local disks. The scheduler considers each PV's node affinity together with the Pod's other constraints.

---

## Useful commands
```bash
kubectl get sc
kubectl get sc <name> -o yaml
kubectl annotate sc <name> storageclass.kubernetes.io/is-default-class=true --overwrite
kubectl get csidriver ; kubectl get node <n> --show-labels    # driver topology keys
```

## Cleanup
```bash
./cleanup.sh       # namespace, extra classes, retained PVs, node dir; re-marks "standard" as default
```
